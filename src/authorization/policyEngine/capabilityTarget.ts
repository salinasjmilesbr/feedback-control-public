import type { Capability } from "../Capability";
import type { TargetRef } from "../policyEngine/types";

/**
 * Contrato FECHADO de compatibilidade capability × tipo de alvo (F4-04,
 * D18 = A ajustada). Allowlist explícita: somente as combinações listadas são
 * semanticamente válidas para as capabilities suportadas pelas F4-03/F4-04.
 * Qualquer combinação não prevista ⇒ incompatível ⇒ DENY (fail-closed).
 *
 * NÃO concede autorização, NÃO substitui capability/scope/relationProvider e
 * NÃO reimplementa regra de domínio.
 */

type TargetType = TargetRef["type"];

const ALLOWED_TARGETS: Record<Capability, readonly TargetType[]> = {
  "collaborator.create": ["collaborator"],
  "collaborator.edit": ["collaborator"],
  "collaborator.list": ["collaborator"],
  "cycle.coordinator.list": ["cycle"],
  "cycle.management.view": ["cycle"],
  "cycle.cancel.manager": ["cycle"],
  "cycle.reopen.manager": ["cycle"],
  "cycle.period.correct.manager": ["cycle"],
  "cycle.team.panel.view": ["cycle"],
  "evaluation.create": ["evaluation", "collaborator", "position"],
  "evaluation.read": ["evaluation", "collaborator", "position"],
  "evaluation.write": ["evaluation", "collaborator", "position"],
  "evaluation.cancel.manager": ["evaluation", "collaborator", "position"],
  "evaluation.reopen.manager": ["evaluation", "collaborator", "position"],
  "evaluation.view.admin": ["evaluation", "collaborator", "position"],
  "evaluation.edit.manager": ["evaluation", "collaborator", "position"],
  "evaluation.edit.coordinator": ["evaluation", "collaborator", "position"],
  "evaluation.edit.board": ["evaluation", "collaborator", "position"],
  "goal.view.admin": ["goal", "collaborator"],
  "goal.approve.manager": ["goal", "collaborator"],
  "goal.approve.coordinator": ["goal", "collaborator"],
  "goal.approve": ["goal", "collaborator"],
  "goal.write": ["goal", "collaborator"],
  "goal.create.own": ["goal", "collaborator"],
  "goal.edit.own": ["goal", "collaborator"],
  "goal.delete.own": ["goal", "collaborator"],
  "goal.progress.own": ["goal", "collaborator"],
  "goal.finalize.own": ["goal", "collaborator"],
  "observation.create": ["observation", "collaborator", "cycle"],
  "observation.edit": ["observation", "collaborator", "cycle"],
  "observation.delete": ["observation", "collaborator", "cycle"],
  "report.view": ["collaborator", "cycle", "evaluation"],
  "settings.manage": ["cycle"],
  "exceptional_access.grant": ["evaluation"],
};

export function isCapabilityTargetCompatible(
  capability: Capability,
  target: TargetRef
): boolean {
  return ALLOWED_TARGETS[capability].includes(target.type);
}
