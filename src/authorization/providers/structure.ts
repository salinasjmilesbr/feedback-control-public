import type { TargetRef } from "../policyEngine/types";

/**
 * Núcleo estrutural da F4-04 (Issue #91): resolução hierárquica
 * DIRECT_REPORTS / DESCENDANTS sobre uma entrada F3-shaped (positions +
 * reporting lines + occupants), SEM qualquer referência a cargo/job_role.
 *
 * A fonte real (positions/reporting/occupations) virá de Supabase na F5; este
 * módulo é o contrato puro e testável, consumido pelo RelationProvider.
 */

/** Aresta de reporting line (flattened): manager null = raiz. */
export interface PositionEdge {
  positionId: string;
  organizationId: string;
  managerPositionId: string | null;
}

/** Occupation vigente de uma posição na data (collaborator null = vaga). */
export interface Occupant {
  positionId: string;
  collaboratorId: string | null;
}

export interface HierarchyScope {
  positionIds: Set<string>;
  collaboratorIds: Set<string>;
}

type Mode = "DIRECT_REPORTS" | "DESCENDANTS";

function buildHierarchyScope(
  mode: Mode,
  actorPositions: readonly string[],
  positions: readonly PositionEdge[],
  occupants: readonly Occupant[],
  organizationId: string
): HierarchyScope {
  const byManager = new Map<string, string[]>();
  for (const p of positions) {
    // tenant: nós de outra organização são ignorados (fail-closed).
    if (p.organizationId !== organizationId) continue;
    if (p.managerPositionId === null) continue;
    const lista = byManager.get(p.managerPositionId) ?? [];
    lista.push(p.positionId);
    byManager.set(p.managerPositionId, lista);
  }

  const occupantByPosition = new Map<string, string | null>();
  for (const o of occupants) {
    occupantByPosition.set(o.positionId, o.collaboratorId);
  }

  const positionIds = new Set<string>();
  const collaboratorIds = new Set<string>();

  const addPosition = (positionId: string) => {
    if (positionIds.has(positionId)) return;
    positionIds.add(positionId);
    const collab = occupantByPosition.get(positionId) ?? null;
    // posição vaga NÃO cria collaborator; vaga não quebra a travessia.
    if (collab !== null) collaboratorIds.add(collab);
  };

  const queue: string[] = [];
  const seen = new Set<string>();

  for (const actorPos of actorPositions) {
    const filhos = byManager.get(actorPos) ?? [];
    for (const filho of filhos) {
      if (!seen.has(filho)) {
        seen.add(filho);
        queue.push(filho);
      }
    }
  }

  while (queue.length > 0) {
    const current = queue.shift()!;
    addPosition(current);
    if (mode === "DESCENDANTS") {
      for (const filho of byManager.get(current) ?? []) {
        if (!seen.has(filho)) {
          seen.add(filho);
          queue.push(filho);
        }
      }
    }
  }

  return { positionIds, collaboratorIds };
}

export function resolveDirectReports(
  actorPositions: readonly string[],
  positions: readonly PositionEdge[],
  occupants: readonly Occupant[],
  organizationId: string
): HierarchyScope {
  return buildHierarchyScope("DIRECT_REPORTS", actorPositions, positions, occupants, organizationId);
}

export function resolveDescendants(
  actorPositions: readonly string[],
  positions: readonly PositionEdge[],
  occupants: readonly Occupant[],
  organizationId: string
): HierarchyScope {
  return buildHierarchyScope("DESCENDANTS", actorPositions, positions, occupants, organizationId);
}

export function targetPertenceAoScope(
  scope: HierarchyScope,
  target: TargetRef
): boolean {
  if (target.type === "collaborator") return scope.collaboratorIds.has(target.id);
  if (target.type === "position") return scope.positionIds.has(target.id);
  return false;
}
