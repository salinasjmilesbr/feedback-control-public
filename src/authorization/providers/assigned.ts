import type { TargetRef } from "../policyEngine/types";

/**
 * ASSIGNED derivado das fontes soberanas F3-08/F3-09 (F4-04, D5/D6).
 * NÃO cria hierarquia, NÃO é wildcard e NÃO duplica os dados: recebe as linhas
 * já materializadas (colegiado / responsabilidade avaliativa) e apenas
 * responde se o ator está atribuído ao alvo avaliativo no ciclo.
 */

export interface CollegiateMembership {
  cycleId: string;
  organizationId: string;
  evaluatedCollaboratorId: string;
  memberCollaboratorId: string;
}

export interface EvaluationResponsibility {
  cycleId: string;
  organizationId: string;
  positionId: string;
  responsibleCollaboratorId: string;
}

/** Alvo avaliativo resolvido (avaliado × ciclo × organização). */
export interface EvaluationTarget {
  cycleId: string;
  organizationId: string;
  evaluatedCollaboratorId: string;
}

export function isCollegiateAssigned(
  actorId: string,
  target: EvaluationTarget,
  memberships: readonly CollegiateMembership[]
): boolean {
  return memberships.some(
    (m) =>
      m.cycleId === target.cycleId &&
      m.organizationId === target.organizationId &&
      m.evaluatedCollaboratorId === target.evaluatedCollaboratorId &&
      m.memberCollaboratorId === actorId
  );
}

export function isEvaluationAssigned(
  actorId: string,
  target: EvaluationTarget,
  responsibilities: readonly EvaluationResponsibility[]
): boolean {
  return responsibilities.some(
    (r) =>
      r.cycleId === target.cycleId &&
      r.organizationId === target.organizationId &&
      r.responsibleCollaboratorId === actorId
  );
}

/** Resolve um TargetRef genérico para o alvo avaliativo (para ASSIGNED). */
export function resolveEvaluationTarget(
  target: TargetRef,
  cycleId: string | undefined,
  organizationId: string
): EvaluationTarget | undefined {
  if (!cycleId) return undefined;
  if (target.type === "evaluation" || target.type === "collaborator") {
    return { cycleId, organizationId, evaluatedCollaboratorId: target.id };
  }
  return undefined;
}
