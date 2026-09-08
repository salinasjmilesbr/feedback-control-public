import type { RelationProvider } from "../policyEngine/types";
import {
  isCollegiateAssigned,
  isEvaluationAssigned,
} from "./assigned";
import type {
  CollegiateMembership,
  EvaluationResponsibility,
  EvaluationTargetResolver,
} from "./assigned";
import {
  resolveDescendants,
  resolveDirectReports,
  targetPertenceAoScope,
} from "./structure";
import type { Occupant, PositionEdge } from "./structure";

/**
 * RelationProvider estrutural da F4-04: compõe hierarchy (DIRECT_REPORTS/
 * DESCENDANTS) e ASSIGNED (colegiado/responsabilidade avaliativa F3-08/09)
 * atrás da MESMA porta `isTargetInScope` do engine F4-03.
 *
 * Sem cargo/job_role: a raiz vem de `resolveActorPositions` (positions
 * confiáveis do ator), a árvore de positions+reporting lines e o ASSIGNED das
 * fontes soberanas.
 */
export interface StructuralRelationInput {
  organizationId: string;
  resolveActorPositions: (actorId: string) => string[];
  positions: readonly PositionEdge[];
  occupants: readonly Occupant[];
  collegiateMemberships: readonly CollegiateMembership[];
  evaluationResponsibilities: readonly EvaluationResponsibility[];
  /**
   * Resolve o TargetRef em alvo avaliativo específico (avaliado + posição +
   * ciclo). Obrigatório para ASSIGNED: sem ele, ASSIGNED falha fechado.
   */
  resolveEvaluationTarget: EvaluationTargetResolver;
}

export function createStructuralRelationProvider(
  input: StructuralRelationInput
): RelationProvider {
  return {
    isTargetInScope: (
      actorId,
      organizationId,
      scope,
      target,
      _date,
      cycleId
    ) => {
      // tenant mismatch = fail-closed
      if (organizationId !== input.organizationId) return false;

      if (scope === "DIRECT_REPORTS" || scope === "DESCENDANTS") {
        const actorPositions = input.resolveActorPositions(actorId);
        if (actorPositions.length === 0) return false;
        const resolved =
          scope === "DIRECT_REPORTS"
            ? resolveDirectReports(actorPositions, input.positions, input.occupants, input.organizationId)
            : resolveDescendants(actorPositions, input.positions, input.occupants, input.organizationId);
        return targetPertenceAoScope(resolved, target);
      }

      if (scope === "ASSIGNED") {
        const aval = input.resolveEvaluationTarget(target, cycleId, input.organizationId);
        if (!aval) return false;
        return (
          isCollegiateAssigned(actorId, aval, input.collegiateMemberships) ||
          isEvaluationAssigned(actorId, aval, input.evaluationResponsibilities)
        );
      }

      if (scope === "ORGANIZATION") {
        // alcance do tenant: o engine já validou o tenant do alvo (passo 4).
        return true;
      }

      // SELF (fluxo-piloto F4-03) e ORGANIZATIONAL_UNIT não são cobertos aqui.
      return false;
    },
  };
}
