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
- **Estado — SQL, fronteira e caminho TS (completo e validado):** migrations
  F5-06 (schema, funções e `20260911020000_f5_06_cutover_leitura_e_ciclo.sql`),
  Edge Function `avaliacoes`, policy/capabilities, ponte matrícula → UUID,
  resolução ano+ciclo, painel do participante e `cutoverAvaliacoesService`.
- **Estado — CUTOVER DAS TELAS (concluído nesta rodada):** nenhuma avaliação
  NOVA é criada/editada/cancelada/reaberta em `localStorage`; a autoridade é o
  PostgreSQL pelo caminho soberano.
  - Telas migradas: `NovoFeedbackPage` (criação + notas/observações/comentário
    final), `EditarFeedbackPage` (leitura do painel + gravação soberana +
    conclusão), `FeedbackDetalhePage` (cancelar/reabrir soberanos),
    `CiclosAvaliacaoPage` (ativação e encerramento).
  - Serviços migrados: `cancelamentoAvaliacaoService`,
    `reaberturaAvaliacaoService`, `cicloEquipeService`
    (`criarAvaliacoesDoCicloAtivado` e `concluirAvaliacoesNoEncerramentoDoCiclo`
    agora **async** e soberanos).
  - Novos módulos: `src/services/acessoAvaliacoesSoberanas.ts` (porta única das
    telas; nenhuma página importa Supabase) e `src/services/origemAvaliacaoTela.ts`
    (FONTE ÚNICA da decisão de origem, por EVIDÊNCIA de cutover).
  - Síncrono → assíncrono: `criarAvaliacoesDoCicloAtivado`,
    `concluirAvaliacoesNoEncerramentoDoCiclo`, `cancelarAvaliacao`,
    `reabrirAvaliacao` e os handlers das quatro telas (com estados de
    processamento/erro preservados).
  - `feedbackStorage` é **somente leitura** para o legado: `saveFeedback` foi
    removida; `updateFeedback`, `persistirCancelamentoAuditadoInterno`,
    `persistirReaberturaAuditadaInterno` e `removerAvaliacaoVaziaNoCleanupInterno`
    existem apenas como barreiras que lançam (fail-closed). Exclusão de ciclo com
    avaliação vazia no legado agora é recusada — a limpeza do legado pertence à
    atividade de importação (fora do escopo, §1.3).
- **Estado — CORREÇÕES PÓS-AUDITORIA GPT (rodada 1):**
  1. **Origem POSTGRES exige EVIDÊNCIA, nunca formato.** `ehIdTecnicoPostgres`
     passou a ser usado SOMENTE como validação de formato, nunca como
     classificação de origem; id legado numérico, textual ou **em formato de
     UUID** não é promovido por isso; nenhuma heurística de data.
  2. **Navegação das avaliações novas.** O livro-caixa de cutover ganhou índices
     de NAVEGAÇÃO (`CHAVE_CICLO_AVALIACOES`) e as telas passaram a abrir a
     avaliação nova pelo painel soberano.
- **Estado — CORREÇÕES PÓS-AUDITORIA GPT (rodada 2, FINAL):**
  1. **Descoberta SOBERANA (localStorage é opcional).** A prova de existência vem
     do SERVIDOR: `resolverLeituraAvaliacao` (`origemAvaliacaoTela.ts`) consulta a
     fronteira confiável para qualquer id candidato e só usa o acervo local quando
     o servidor responde `NOT_FOUND` (o código público do erro é exposto em
     `ResultadoCutover.codigo` para essa distinção — sem inspeção de texto).
     Consequências: `localStorage` apagado, outro navegador/dispositivo,
     livro-caixa ausente/corrompido e **URL soberana aberta diretamente** não
     escondem uma avaliação real; falha de backend/indeterminação é fail-closed e
     nunca vira leitura local silenciosa; `NOT_FOUND` e negação permanecem
     indistinguíveis (sem vazar existência cross-tenant).
     No SQL, ausência de ocorrência vigente do ator no painel passou a devolver
     `NULL` (resultado "sem painel") em vez de exceção, permitindo distinguir
     "não existe/não acessível" de "falha real".
  2. **Índices de navegação ISOLADOS por organização.** `chaveAnoCiclo` e
     `chaveCicloColaborador` passaram a incluir `organizationId`
     (`org|ano-ciclo`), e `registrarAvaliacoesDoCiclo`/`lerAvaliacoesDoCiclo`/
     `lerAvaliacaoNovaDoColaboradorNoCiclo`/`esquecerAvaliacaoNovaDoColaboradorNoCiclo`
     recebem a organização. Mesma matrícula/ano/ciclo em orgs diferentes não
     colide; trocar de organização ativa não reutiliza índice alheio. A
     organização ali é apenas NAMESPACE DE CACHE — não é prova de tenant nem
     autorização (toda operação revalida server-side).
  3. **Preflight de duplicidade validado no servidor.** `NovoFeedbackPage` não
     bloqueia mais só pelo cache: confirma a existência na fronteira confiável e,
     se a entrada estiver obsoleta, esquece o cache e segue com a criação
     legítima. A autoridade da unicidade continua sendo o índice único parcial do
     banco, e nada é criado localmente.
- **Telas que ainda leem SOMENTE o legado (justificativa):**
  - `CiclosAvaliacaoPage`/`PainelCicloPage`/`relatorioService`: o painel é
    montado pelo domínio de **ciclos**, que ainda vive em `localStorage`
    (migração de ciclos é outra atividade — D15). Enquanto o ciclo não existir no
    banco, não há avaliação nova daquele ciclo a listar; quando existir, o índice
    de navegação é o caminho. Nenhuma autoridade local é exercida.
  - `ColaboradorDetalhePage`: lista o histórico administrativo do acervo legado;
    a avaliação nova é alcançável pelo índice/painel. Adotar a leitura soberana
    nessa listagem é aditivo.
- **Pendências/limitações conhecidas (não bloqueiam o critério de conclusão):**
  1. **Gravação de ciclo (entidade `evaluation_cycles`) é de outra atividade**
     (D15). Sem o ciclo correspondente no banco, `evaluation.criar` é recusado e
     a tela reporta quantas avaliações ficaram **bloqueadas** (nunca cria local).
  2. **Remoção de nota**: `evaluation_gravar_notas` aceita notas `1..5`; limpar
     uma nota já gravada não a apaga (não há API de exclusão). O valor anterior
     permanece — alteração de contrato exigiria nova `Q#`.
  3. **Listagem administrativa do legado** (item acima) permanece legado.
  4. **Descoberta de id fora da URL**: sem estado local, o produto alcança a
     avaliação pela URL/painel; uma listagem soberana "por ciclo/colaborador"
     (Edge + Policy Engine) é evolução aditiva e depende da migração de ciclos.
- **Validação executada nesta rodada (todo exit 0):** `npm test` (83 arquivos,
  1062 testes), `npm run build`, `npm run lint`, `git diff --check`;
  validadores SQL no Supabase local — `01-cenario-f5-06.sql`,
  `02-validar-f5-06.sql` (25 PASS), `03-validar-f5-06-cutover.sql` (6 PASS),
  `01-cenario-f4-08.sql`, `02-validar-f4-08.sql` (56 PASS),
  `03-validar-f4-08-mutacoes.sql` (8 PASS).
- **Contexto do repositório:** `main` contém F4 e F5-01..F5-05; a F5-06 é a
  atividade em curso nesta branch.
- **Próximos passos:** abrir PR quando solicitado; eventuais follow-ups são os
  três itens de "pendências/limitações conhecidas".
