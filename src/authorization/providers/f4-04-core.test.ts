import { describe, expect, it } from "vitest";
import { isCapabilityTargetCompatible } from "../policyEngine/capabilityTarget";
import { decidir } from "../policyEngine/policyEngine";
import type { PolicyEngineProviders, TargetRef } from "../policyEngine/types";
import {
  isCollegiateAssigned,
  isEvaluationAssigned,
} from "./assigned";
import type { CollegiateMembership, EvaluationResponsibility } from "./assigned";
import {
  createStructuralRelationProvider,
} from "./structuralRelation";
import {
  resolveDescendants,
  resolveDirectReports,
} from "./structure";
import type { Occupant, PositionEdge } from "./structure";

const ORG = "org-a";
const OTHER = "org-b";

// positions (edges) e occupants sintéticos (F3-shaped; sem cargo)
const positions: PositionEdge[] = [
  { positionId: "p0", organizationId: ORG, managerPositionId: null }, // DIR (raiz)
  { positionId: "p1", organizationId: ORG, managerPositionId: "p0" }, // GER
  { positionId: "p2", organizationId: ORG, managerPositionId: "p1" }, // COORD
  { positionId: "p8", organizationId: ORG, managerPositionId: "p1" }, // COORD paralelo
  { positionId: "p3", organizationId: ORG, managerPositionId: "p2" }, // AN1
  { positionId: "p4", organizationId: ORG, managerPositionId: "p2" }, // AN2
  { positionId: "p5", organizationId: ORG, managerPositionId: "p2" }, // vaga intermediária
  { positionId: "p6", organizationId: ORG, managerPositionId: "p5" }, // DEEP (abaixo da vaga)
  { positionId: "p7", organizationId: ORG, managerPositionId: "p5" }, // DEEP2
  { positionId: "p9", organizationId: ORG, managerPositionId: "p8" }, // AN3 (sob coord paralelo)
  { positionId: "px", organizationId: OTHER, managerPositionId: "p1" }, // cross-tenant
];

const occupants: Occupant[] = [
  { positionId: "p0", collaboratorId: "c_dir" },
  { positionId: "p1", collaboratorId: "c_ger" },
  { positionId: "p2", collaboratorId: "c_coord" },
  { positionId: "p8", collaboratorId: "c_other" },
  { positionId: "p3", collaboratorId: "c_an1" },
  { positionId: "p4", collaboratorId: "c_an2" },
  { positionId: "p5", collaboratorId: null }, // vaga
  { positionId: "p6", collaboratorId: "c_deep" },
  { positionId: "p7", collaboratorId: "c_an1" }, // mesma pessoa em outro ramo
  { positionId: "p9", collaboratorId: "c_an3" },
  { positionId: "px", collaboratorId: "c_orgb" },
];

const memberships: CollegiateMembership[] = [
  { cycleId: "c1", organizationId: ORG, evaluatedCollaboratorId: "c_an1", memberCollaboratorId: "c_avaliador" },
];

const responsibilities: EvaluationResponsibility[] = [
  { cycleId: "c1", organizationId: ORG, positionId: "p3", responsibleCollaboratorId: "c_ger" },
];

describe("F4-04 — hierarchy (structure)", () => {
  it("DIRECT_REPORTS: subordinados diretos (positions + occupants), vaga sem collaborator", () => {
    const scope = resolveDirectReports(["p2"], positions, occupants, ORG);
    expect([...scope.positionIds].sort()).toEqual(["p3", "p4", "p5"]);
    expect([...scope.collaboratorIds].sort()).toEqual(["c_an1", "c_an2"]);
  });

  it("DESCENDANTS: árvore completa, atravessa vaga intermediária e deduplica collaborator", () => {
    const scope = resolveDescendants(["p1"], positions, occupants, ORG);
    expect([...scope.positionIds].sort()).toEqual(
      ["p2", "p3", "p4", "p5", "p6", "p7", "p8", "p9"].sort()
    );
    // c_an1 aparece em p3 e p7 (deduplicado); vaga p5 não cria collaborator.
    expect([...scope.collaboratorIds].sort()).toEqual(
      ["c_an1", "c_an2", "c_an3", "c_coord", "c_deep", "c_other"].sort()
    );
  });

  it("DESCENDANTS: coordenação paralela não é alcançada pelo outro coordenador", () => {
    const coord = resolveDescendants(["p2"], positions, occupants, ORG);
    expect(coord.collaboratorIds.has("c_other")).toBe(false);
    expect(coord.collaboratorIds.has("c_an3")).toBe(false);
  });

  it("multi-positions: união de todas as positions do ator", () => {
    const scope = resolveDirectReports(["p2", "p8"], positions, occupants, ORG);
    expect([...scope.positionIds].sort()).toEqual(["p3", "p4", "p5", "p9"]);
  });

  it("tenant: aresta cross-org é ignorada (fail-closed)", () => {
    const scope = resolveDescendants(["p1"], positions, occupants, ORG);
    expect(scope.collaboratorIds.has("c_orgb")).toBe(false);
    expect(scope.positionIds.has("px")).toBe(false);
  });

  it("ator sem occupation: conjunto vazio", () => {
    expect(resolveDescendants([], positions, occupants, ORG).positionIds.size).toBe(0);
    expect(resolveDirectReports([], positions, occupants, ORG).collaboratorIds.size).toBe(0);
  });

  it("collaborator fora da árvore não pertence ao scope", () => {
    const scope = resolveDescendants(["p2"], positions, occupants, ORG);
    expect(scope.collaboratorIds.has("c_ghost")).toBe(false);
  });
});

describe("F4-04 — ASSIGNED (colegiado / responsabilidade avaliativa)", () => {
  const target = { cycleId: "c1", organizationId: ORG, evaluatedCollaboratorId: "c_an1" };

  it("colegiado permite somente o membro atribuído", () => {
    expect(isCollegiateAssigned("c_avaliador", target, memberships)).toBe(true);
    expect(isCollegiateAssigned("c_coord", target, memberships)).toBe(false);
  });

  it("responsabilidade avaliativa (F3-09) reconhece o responsável", () => {
    expect(isEvaluationAssigned("c_ger", target, responsibilities)).toBe(true);
    expect(isEvaluationAssigned("c_coord", target, responsibilities)).toBe(false);
  });

  it("snapshot/ciclo é soberano (outro ciclo => sem atribuição)", () => {
    expect(isCollegiateAssigned("c_avaliador", { ...target, cycleId: "c2" }, memberships)).toBe(false);
  });

  it("RelationProvider: ASSIGNED não cria hierarchy (alvo fora do avaliado)", () => {
    const relation = createStructuralRelationProvider({
      organizationId: ORG,
      resolveActorPositions: () => [],
      positions,
      occupants,
      collegiateMemberships: memberships,
      evaluationResponsibilities: responsibilities,
    });
    const aval: TargetRef = { type: "collaborator", id: "c_an1" };
    const fora: TargetRef = { type: "collaborator", id: "c_deep" };
    expect(relation.isTargetInScope("c_avaliador", ORG, "ASSIGNED", aval, new Date(), "c1")).toBe(true);
    expect(relation.isTargetInScope("c_avaliador", ORG, "ASSIGNED", fora, new Date(), "c1")).toBe(false);
  });
});

describe("F4-04 — contrato capability × target (D18)", () => {
  it("rejeita combinações semanticamente impossíveis", () => {
    expect(isCapabilityTargetCompatible("evaluation.write", { type: "goal", id: "x" })).toBe(false);
    expect(isCapabilityTargetCompatible("goal.write", { type: "evaluation", id: "x" })).toBe(false);
    expect(isCapabilityTargetCompatible("observation.create", { type: "goal", id: "x" })).toBe(false);
  });

  it("permite subtargets válidos", () => {
    expect(isCapabilityTargetCompatible("evaluation.write", { type: "collaborator", id: "x" })).toBe(true);
    expect(isCapabilityTargetCompatible("goal.write", { type: "goal", id: "x" })).toBe(true);
  });

  it("engine nega capability incompatível com target (TARGET_INCOMPATIBLE)", () => {
    const providers: PolicyEngineProviders = {
      identity: { isProfileActive: () => true, isMembershipActive: () => true },
      capabilities: { hasCapability: () => true },
      scopes: { getActiveScopes: () => ["DIRECT_REPORTS"] },
      targets: { resolveTargetTenant: () => ORG },
      relations: {
        isTargetInScope: () => true,
      },
    };
    const decision = decidir(
      {
        actor: { actorId: "1", organizationId: ORG },
        capability: "goal.write",
        target: { type: "evaluation", id: "x" },
        context: { date: new Date() },
        domainState: { allows: () => true },
      },
      providers
    );
    expect(decision.allowed).toBe(false);
    expect(decision.denial?.reason).toBe("TARGET_INCOMPATIBLE");
    expect(decision.denial?.publicCode).toBe("FORBIDDEN");
  });
});
