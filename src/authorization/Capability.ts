export type Capability =
  // ---------------------------------------------------------------
  // Catálogo CANÔNICO (F4-09 §6.3): capability = AÇÃO, nunca papel.
  // Papel (gerente/coordenador/colegiado) é resolvido por relação,
  // scope, target e domainState — nunca por nome de capability.
  // ---------------------------------------------------------------
  | "collaborator.create"
  | "collaborator.edit"
  | "collaborator.read"
  | "cycle.read"
  | "cycle.manage"
  | "cycle.cancel"
  | "cycle.reopen"
  | "cycle.period.correct"
  | "evaluation.create"
  | "evaluation.read"
  | "evaluation.write"
  | "evaluation.cancel"
  | "evaluation.reopen"
  | "goal.read"
  | "goal.write"
  | "goal.approve"
  | "observation.read"
  | "observation.create"
  | "observation.edit"
  | "observation.delete"
  | "report.read"
  | "settings.manage"
  | "exceptional_access.grant"
  | "pilot_full_access.grant"
  // ---------------------------------------------------------------
  // ALIASES LEGADOS (depreciados — migração/regressão apenas).
  // Nunca usados como fonte de decisão runtime; mapeados ao canônico
  // por `canonicalizarCapability` (src/authorization/canonical.ts).
  // ---------------------------------------------------------------
  | "collaborator.list"
  | "cycle.coordinator.list"
  | "cycle.management.view"
  | "cycle.cancel.manager"
  | "cycle.reopen.manager"
  | "cycle.period.correct.manager"
  | "cycle.team.panel.view"
  | "evaluation.cancel.manager"
  | "evaluation.reopen.manager"
  | "evaluation.view.admin"
  | "evaluation.edit.manager"
  | "evaluation.edit.coordinator"
  | "evaluation.edit.board"
  | "goal.view.admin"
  | "goal.approve.manager"
  | "goal.approve.coordinator"
  | "goal.create.own"
  | "goal.edit.own"
  | "goal.delete.own"
  | "goal.progress.own"
  | "goal.finalize.own"
  | "report.view";
