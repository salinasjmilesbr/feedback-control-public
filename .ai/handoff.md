# Virtus — Handoff operacional

Estado operacional de retomada. GitHub é a fonte de verdade para Issues, PRs e decisões; regras permanentes estão em AGENTS.md/.ai/* e contratos nos desenhos fechados. Atualizar em mudança de fase ou obsolescência material; não duplicar contexto estável.

## Estado vigente
- Incremento 0 de Avaliações concluído; Incremento 1 — Fronteiras de Leitura concluído/mergeado.
- #427 concluída/mergeada: máximo uma ocupação por colaborador/data, sem sobreposição; responsabilidades temporárias não são ocupações.
- #429 concluída/mergeada: protocolo portátil de worktrees/orquestração e F3-05/F3-08/F4-02 no CI conforme Issue/PR.
- #431 é a próxima atividade, desenho do Incremento 2; arquitetura ainda não iniciada.
- #421 pausada até contratos server-side; #293 posterior à validação da jornada soberana.
- #414 adiada/não contratual; migrations divergentes locais não representam produto.

## Ambiente deste host (não portátil)
- Raiz local preferencial: D:\Projetos\VirtusWorktrees.
- origin/main está em 20519c420d144543a13efacc49c3aec7a1e065b9; a worktree #432 foi criada corretamente nesse mesmo SHA.
- Somente a worktree local D:\Projetos\VirtusWorktrees\main-clean (branch main) está temporariamente dois commits atrás, em 09c9cedf9f50c46f79f25673416e314644e5e5fc. É uma pendência operacional local, não uma divergência da baseline da #432; deixar intacta e sincronizar deliberadamente antes de usá-la.
- Checkout OneDrive reservado à #421; worktrees novas fora do checkout/OneDrive, node_modules, cache e outras worktrees. Executar preflight portátil de .ai/workflow.md antes de git worktree add.
- Worktree #432: D:\Projetos\VirtusWorktrees\issue432, branch docs/issue-432-checkpoint-orchestration, base origin/main 20519c420d144543a13efacc49c3aec7a1e065b9. Sem commit/push/PR.
- Preservar backup temporário da antiga .inc1w no SSD até revisão posterior; worktrees antigas removidas não são referências vigentes.

## Retomada e entrega
1. Conferir branch, SHA, base, status, worktrees e Issue/PR; confirmar contrato e pipeline.
2. Handoff entre agentes persistido, não só chat. Diagnosticar falhas antes de novo ciclo fix/CI.
3. Implementar em lote, autoauditar e rodar gates proporcionais; não enfraquecer assertions nem contornar gate.
4. PR + CI antecipado após push autorizado; auditar SHA. Correção gera novo SHA/CI e nova auditoria/certificação. Merge explícito somente com CI verde no SHA auditado.
5. Registrar gates reais, riscos, pendências, próximo responsável e nota 0–10 justificada conforme .ai/workflow.md.

Histórico: #427/#428 e #429/#430; roadmap em docs/plano-mestre.md; arquitetura em .ai/architecture-rules.md; dívidas em docs/dividas-tecnicas.md.
