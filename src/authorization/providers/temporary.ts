import type { Capability } from "../Capability";
import type {
  ResponsibilityType,
  ScopeType,
  TargetRef,
  TemporaryGrant,
  TemporaryProvider,
} from "../policyEngine/types";
import type { EvaluationTargetResolver } from "./assigned";
import { resolveDescendants, targetPertenceAoScope } from "./structure";
import type { Occupant, PositionEdge } from "./structure";

/**
 * Origem temporária da F4-05 (Issue #92): temporary_responsibilities (F3-06)
 * resolvidas POR DATA, sem cargo, sem hierarquia paralela e sem herança das
 * capabilities/scopes do titular (D1/D3/D4/D5/D12).
 *
 * A fonte real (temporary_responsibilities + positions/reporting/occupations +
 * snapshots F3-08/F3-09) virá de Supabase na F5; este módulo é o contrato puro
 * e testável, consumido pelo policy engine através do `TemporaryProvider`.
 */

/** Entrada F3-shaped de uma temporary responsibility (F3-06). */
export interface TemporaryResponsibility {
  id: string;
  organizationId: string;
  /** Posição formal alvo da responsabilidade (a raiz exclusiva do grant temporário). */
  organizationalPositionId: string;
  substituteCollaboratorId: string;
  responsibilityType: ResponsibilityType;
  validFrom: Date;
  validTo: Date;
}

/** Regra fechada capability × scope (D3). */
interface CapabilityRule {
  capability: Capability;
  scope: ScopeType;
}

const OPERATIONAL_RULES: readonly CapabilityRule[] = [
  { capability: "collaborator.list", scope: "DESCENDANTS" },
  { capability: "observation.create", scope: "DESCENDANTS" },
  { capability: "observation.edit", scope: "DESCENDANTS" },
  { capability: "observation.delete", scope: "DESCENDANTS" },
  { capability: "goal.approve", scope: "DESCENDANTS" },
  { capability: "goal.view.admin", scope: "DESCENDANTS" },
  { capability: "report.view", scope: "DESCENDANTS" },
];

const EVALUATIVE_RULES: readonly CapabilityRule[] = [
  { capability: "evaluation.create", scope: "ASSIGNED" },
  { capability: "evaluation.read", scope: "ASSIGNED" },
  { capability: "evaluation.write", scope: "ASSIGNED" },
];

/**
 * Contrato FECHADO responsibility_type × capability (D3, revisão aprovada).
 * Allowlist explícita, sem prefixo genérico, sem wildcard e sem copiar o
 * titular. `operational_evaluative` = união dos dois conjuntos.
 */
export const TEMPORARY_RESPONSIBILITY_CAPABILITIES: Record<
  ResponsibilityType,
  readonly CapabilityRule[]
> = {
  operational: OPERATIONAL_RULES,
  evaluative: EVALUATIVE_RULES,
  operational_evaluative: [...OPERATIONAL_RULES, ...EVALUATIVE_RULES],
};

function rulesForType(type: string): readonly CapabilityRule[] {
  const map = TEMPORARY_RESPONSIBILITY_CAPABILITIES as Record<
    string,
    readonly CapabilityRule[] | undefined
  >;
  return map[type] ?? []; // tipo desconhecido => sem capabilities (fail-closed)
}

/** Responsabilidades vigentes do ator na data, mesmo tenant (F3-06). */
export function getActiveTemporaryResponsibilities(
  actorId: string,
  organizationId: string,
  date: Date,
  responsibilities: readonly TemporaryResponsibility[]
): TemporaryResponsibility[] {
  return responsibilities.filter(
    (r) =>
      r.organizationId === organizationId &&
      r.substituteCollaboratorId === actorId &&
      r.validFrom <= date &&
      r.validTo > date
  );
}

/** União deduplicada de capabilities elegíveis pelas responsabilidades vigentes. */
export function getEligibleTemporaryCapabilities(
  actorId: string,
  organizationId: string,
  date: Date,
  responsibilities: readonly TemporaryResponsibility[]
): Capability[] {
  const active = getActiveTemporaryResponsibilities(
    actorId,
    organizationId,
    date,
    responsibilities
  );
  const caps = new Set<Capability>();
  for (const r of active) {
    for (const rule of rulesForType(r.responsibilityType)) {
      caps.add(rule.capability);
    }
  }
  return [...caps];
}

/** Mapa posição → posição superior (mesmo tenant), a partir das reporting lines. */
function buildManagerByPosition(
  positions: readonly PositionEdge[],
  organizationId: string
): Map<string, string> {
  const map = new Map<string, string>();
  for (const p of positions) {
    if (p.organizationId !== organizationId) continue;
    if (p.managerPositionId === null) continue;
    map.set(p.positionId, p.managerPositionId);
  }
  return map;
}

/** Alcance DESCENDANTS do grant temporário (raiz = position substituída). */
function isOperationalTargetInScope(
  substitutedPositionId: string,
  target: TargetRef,
  positions: readonly PositionEdge[],
  occupants: readonly Occupant[],
  organizationId: string
): boolean {
  const scope = resolveDescendants(
    [substitutedPositionId],
    positions,
    occupants,
    organizationId
  );
  return targetPertenceAoScope(scope, target);
}

/**
 * Alcance ASSIGNED vivo do grant avaliativo temporário (D8/D9): a posição
 * substituída deve ser a posição superior (avaliadora) da posição do avaliado,
 * e o contexto precisa ser VIVO (não congelado por F3-08/F3-09). Congelado ou
 * indistinguível => não autoriza (fail-closed, fontes congeladas soberanas).
 */
function isEvaluativeTargetInScope(
  substitutedPositionId: string,
  target: TargetRef,
  cycleId: string | undefined,
  organizationId: string,
  positions: readonly PositionEdge[],
  resolveEvaluationTarget: EvaluationTargetResolver,
  isEvaluationFrozen: (
    target: TargetRef,
    cycleId: string | undefined,
    organizationId: string
  ) => boolean | undefined
): boolean {
  const aval = resolveEvaluationTarget(target, cycleId, organizationId);
  if (!aval) return false;

  const managerByPosition = buildManagerByPosition(positions, organizationId);
  if (managerByPosition.get(aval.positionId) !== substitutedPositionId) {
    return false;
  }

  // vivo × congelado: true (congelado) ou undefined (indistinguível) => nega.
  return isEvaluationFrozen(target, cycleId, organizationId) === false;
}

export interface TemporaryRelationInput {
  organizationId: string;
  responsibilities: readonly TemporaryResponsibility[];
  positions: readonly PositionEdge[];
  occupants: readonly Occupant[];
  /** Resolve TargetRef em alvo avaliativo (avaliado + posição + ciclo), como na F4-04. */
  resolveEvaluationTarget: EvaluationTargetResolver;
  /**
   * true = contexto congelado por F3-08/F3-09 (soberano); false = vivo;
   * undefined = não é possível distinguir (fail-closed). Só o contexto vivo
   * autoriza o grant avaliativo temporário.
   */
  isEvaluationFrozen: (
    target: TargetRef,
    cycleId: string | undefined,
    organizationId: string
  ) => boolean | undefined;
}

/** Cria o TemporaryProvider a partir de entrada F3-shaped pura (sem cargo). */
export function createTemporaryProvider(
  input: TemporaryRelationInput
): TemporaryProvider {
  return {
    getEligibleCapabilities: (actorId, organizationId, date) =>
      getEligibleTemporaryCapabilities(
        actorId,
        organizationId,
        date,
        input.responsibilities
      ),

    resolveTemporaryGrants: (
      actorId,
      organizationId,
      capability,
      target,
      date,
      cycleId
    ) => {
      if (organizationId !== input.organizationId) return [];

      const active = getActiveTemporaryResponsibilities(
        actorId,
        organizationId,
        date,
        input.responsibilities
      );

      const grants: TemporaryGrant[] = [];
      const seen = new Set<string>();

      for (const r of active) {
        for (const rule of rulesForType(r.responsibilityType)) {
          if (rule.capability !== capability) continue;

          const inScope =
            rule.scope === "ASSIGNED"
              ? isEvaluativeTargetInScope(
                  r.organizationalPositionId,
                  target,
                  cycleId,
                  input.organizationId,
                  input.positions,
                  input.resolveEvaluationTarget,
                  input.isEvaluationFrozen
                )
              : isOperationalTargetInScope(
                  r.organizationalPositionId,
                  target,
                  input.positions,
                  input.occupants,
                  input.organizationId
                );

          if (!inScope) continue;

          const origin = `temporary:${r.id}`;
          if (seen.has(origin)) continue;
          seen.add(origin);

          grants.push({
            origin,
            responsibilityId: r.id,
            responsibilityType: r.responsibilityType,
            capability,
            scope: rule.scope,
            substitutedPositionId: r.organizationalPositionId,
          });
        }
      }

      return grants;
    },
  };
}
