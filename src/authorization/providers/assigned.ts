import type { TargetRef } from "../policyEngine/types.ts";

/**
 * ASSIGNED derivado das fontes soberanas F3-08/F3-09 (F4-04, D5/D6).
 * NÃO cria hierarquia, NÃO é wildcard e NÃO duplica os dados.
 *
 * Correlação específica (F3-09): a responsabilidade avaliativa é keyed por
 * (ciclo, organização, posição, avaliado) — o alvo avaliativo precisa de
 * positionId + evaluatedCollaboratorId para nunca casar "qualquer avaliação do
 * ciclo".
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
  /** Posição avaliada (chave da responsabilidade F3-09). */
  positionId: string;
  /** Avaliado do snapshot do ciclo (F3-08/09). */
  evaluatedCollaboratorId: string;
  responsibleCollaboratorId: string;
}

/** Alvo avaliativo resolvido (avaliado × posição × ciclo × organização). */
export interface EvaluationTarget {
  cycleId: string;
  organizationId: string;
  evaluatedCollaboratorId: string;
  positionId: string;
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
      r.positionId === target.positionId &&
      r.evaluatedCollaboratorId === target.evaluatedCollaboratorId &&
      r.responsibleCollaboratorId === actorId
  );
}

/**
 * Contrato do resolver de alvo avaliativo: converte um TargetRef genérico em
 * EvaluationTarget (avaliado + posição + ciclo) ou undefined. O adapter real
 * (F5) deriva a posição/avaliado da avaliação concreta.
 */
export type EvaluationTargetResolver = (
  target: TargetRef,
  cycleId: string | undefined,
  organizationId: string
) => EvaluationTarget | undefined;
