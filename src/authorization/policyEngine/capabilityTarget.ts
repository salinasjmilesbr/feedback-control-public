import type { Capability } from "../Capability.ts";
import type { TargetRef } from "./types.ts";

/**
 * Contrato FECHADO de compatibilidade capability × tipo de alvo (F4-04,
 * D18 = A ajustada). Allowlist explícita: somente as combinações listadas são
 * semanticamente válidas. Qualquer combinação não prevista ⇒ DENY (fail-closed).
 *
 * F4-09 (Q1): inclui o catálogo CANÔNICO (ação) e mantém os aliases legados
 * mapeados à mesma semântica de alvo (migração).
 */

type TargetType = TargetRef["type"];

const ALLOWED_TARGETS: Record<Capability, readonly TargetType[]> = {
  // Canônicas
  "collaborator.create": ["collaborator"],
  "collaborator.edit": ["collaborator"],
  "collaborator.read": ["collaborator"],
  "cycle.read": ["cycle", "collaborator"],
  "cycle.manage": ["cycle"],
  "cycle.cancel": ["cycle"],
  "cycle.reopen": ["cycle"],
  "cycle.period.correct": ["cycle"],
  "evaluation.create": ["evaluation", "collaborator", "position"],
  "evaluation.read": ["evaluation", "collaborator", "position"],
  "evaluation.write": ["evaluation", "collaborator", "position"],
  "evaluation.cancel": ["evaluation", "collaborator", "position"],
  "evaluation.reopen": ["evaluation", "collaborator", "position"],
  "goal.read": ["goal", "collaborator"],
  "goal.write": ["goal", "collaborator"],
  "goal.approve": ["goal", "collaborator"],
  "observation.read": ["observation", "collaborator", "cycle"],
  "observation.create": ["observation", "collaborator", "cycle"],
  "observation.edit": ["observation", "collaborator", "cycle"],
  "observation.delete": ["observation", "collaborator", "cycle"],
  "report.read": ["collaborator", "cycle", "evaluation"],
  "settings.manage": ["cycle"],
  // Administrativas/controle (F5-04 D14/D15): não possuem alvo de domínio
  // funcional no vocabulário atual do engine; fail-closed (nenhum target é
  // compatível). São resolvidas server-side, nunca via TargetRef funcional.
  "membership.read": [],
  "membership.manage": [],
  "access_role.manage": [],
  "org.structure.manage": [],
  "org.catalog.manage": [],
  "exceptional_access.grant": ["evaluation"],
  "pilot_full_access.grant": ["collaborator", "cycle", "goal", "observation"],
  // Aliases legados (mesma semântica de alvo do canônico)
  "collaborator.list": ["collaborator"],
  "cycle.coordinator.list": ["cycle"],
  "cycle.management.view": ["cycle"],
  "cycle.cancel.manager": ["cycle"],
  "cycle.reopen.manager": ["cycle"],
  "cycle.period.correct.manager": ["cycle"],
  "cycle.team.panel.view": ["cycle"],
  "evaluation.cancel.manager": ["evaluation", "collaborator", "position"],
  "evaluation.reopen.manager": ["evaluation", "collaborator", "position"],
  "evaluation.view.admin": ["evaluation", "collaborator", "position"],
  "evaluation.edit.manager": ["evaluation", "collaborator", "position"],
  "evaluation.edit.coordinator": ["evaluation", "collaborator", "position"],
  "evaluation.edit.board": ["evaluation", "collaborator", "position"],
  "goal.view.admin": ["goal", "collaborator"],
  "goal.approve.manager": ["goal", "collaborator"],
  "goal.approve.coordinator": ["goal", "collaborator"],
  "goal.create.own": ["goal", "collaborator"],
  "goal.edit.own": ["goal", "collaborator"],
  "goal.delete.own": ["goal", "collaborator"],
  "goal.progress.own": ["goal", "collaborator"],
  "goal.finalize.own": ["goal", "collaborator"],
  "report.view": ["collaborator", "cycle", "evaluation"],
};

export function isCapabilityTargetCompatible(
  capability: Capability,
  target: TargetRef
): boolean {
  const tipos = ALLOWED_TARGETS[capability];
  return tipos !== undefined && tipos.includes(target.type);
}
