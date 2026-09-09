import type { Capability } from "./Capability";

/**
 * Reconciliação do vocabulário de capabilities (F4-09 Q1, §6.3):
 * capability = AÇÃO. Os aliases legados que codificavam papel são mapeados à
 * ação canônica correspondente. Nenhum mapeamento `funcao → capability` existe
 * em runtime; este mapa é somente capability → capability (migração).
 */
const ALIASES_LEGADOS: Readonly<Record<string, Capability>> = {
  "collaborator.list": "collaborator.read",
  "cycle.coordinator.list": "cycle.read",
  "cycle.management.view": "cycle.read",
  "cycle.cancel.manager": "cycle.cancel",
  "cycle.reopen.manager": "cycle.reopen",
  "cycle.period.correct.manager": "cycle.period.correct",
  "cycle.team.panel.view": "cycle.read",
  "evaluation.cancel.manager": "evaluation.cancel",
  "evaluation.reopen.manager": "evaluation.reopen",
  "evaluation.view.admin": "evaluation.read",
  "evaluation.edit.manager": "evaluation.write",
  "evaluation.edit.coordinator": "evaluation.write",
  "evaluation.edit.board": "evaluation.write",
  "goal.view.admin": "goal.read",
  "goal.approve.manager": "goal.approve",
  "goal.approve.coordinator": "goal.approve",
  "goal.create.own": "goal.write",
  "goal.edit.own": "goal.write",
  "goal.delete.own": "goal.write",
  "goal.progress.own": "goal.write",
  "goal.finalize.own": "goal.write",
  "report.view": "report.read",
};

export function canonicalizarCapability(capability: Capability): Capability {
  return (ALIASES_LEGADOS[capability] as Capability | undefined) ?? capability;
}
