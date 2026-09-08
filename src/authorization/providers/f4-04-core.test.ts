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
  { cycleId: "c1", organizationId: ORG, positionId: "p3", evaluatedCollaboratorId: "c_an1", responsibleCollaboratorId: "c_ger" },
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
  const target = { cycleId: "c1", organizationId: ORG, evaluatedCollaboratorId: "c_an1", positionId: "p3" };
  const targetB = { cycleId: "c1", organizationId: ORG, evaluatedCollaboratorId: "c_an2", positionId: "p4" };

  // mapper sintético TargetRef → EvaluationTarget (avaliado + posição)
  const positionPorAvaliado: Record<string, string> = { c_an1: "p3", c_an2: "p4" };
  const resolveEvaluationTarget = (t: TargetRef, cycleId: string | undefined, org: string) => {
    if (!cycleId || (t.type !== "collaborator" && t.type !== "evaluation")) return undefined;
    const positionId = positionPorAvaliado[t.id];
    return positionId
      ? { cycleId, organizationId: org, evaluatedCollaboratorId: t.id, positionId }
      : undefined;
  };

  it("colegiado permite somente o membro atribuído", () => {
    expect(isCollegiateAssigned("c_avaliador", target, memberships)).toBe(true);
    expect(isCollegiateAssigned("c_coord", target, memberships)).toBe(false);
  });

  it("responsabilidade avaliativa (F3-09) reconhece o responsável do alvo específico", () => {
    expect(isEvaluationAssigned("c_ger", target, responsibilities)).toBe(true);
    expect(isEvaluationAssigned("c_coord", target, responsibilities)).toBe(false);
  });

  it("responsabilidade de A não vira wildcard para B no mesmo ciclo/tenant", () => {
    // ator responsável por A (p3/c_an1); consulta B (p4/c_an2) => false
    expect(isEvaluationAssigned("c_ger", targetB, responsibilities)).toBe(false);
  });

  it("snapshot/ciclo é soberano (outro ciclo => sem atribuição)", () => {
    expect(isCollegiateAssigned("c_avaliador", { ...target, cycleId: "c2" }, memberships)).toBe(false);
    expect(isEvaluationAssigned("c_ger", { ...target, cycleId: "c2" }, responsibilities)).toBe(false);
  });

  it("RelationProvider: ASSIGNED correlaciona posição/avaliado (A vs B)", () => {
    const relation = createStructuralRelationProvider({
      organizationId: ORG,
      resolveActorPositions: () => [],
      positions,
      occupants,
      collegiateMemberships: memberships,
      evaluationResponsibilities: responsibilities,
      resolveEvaluationTarget,
    });
    const alvoA: TargetRef = { type: "collaborator", id: "c_an1" };
    const alvoB: TargetRef = { type: "collaborator", id: "c_an2" };
    expect(relation.isTargetInScope("c_ger", ORG, "ASSIGNED", alvoA, new Date(), "c1")).toBe(true);
    expect(relation.isTargetInScope("c_ger", ORG, "ASSIGNED", alvoB, new Date(), "c1")).toBe(false);
    // colegiado também é específico ao avaliado (sem hierarchy/wildcard)
    expect(relation.isTargetInScope("c_avaliador", ORG, "ASSIGNED", alvoB, new Date(), "c1")).toBe(false);
  });

  it("Policy Engine: ASSIGNED A permite A e nega B (DENY)", () => {
    const relation = createStructuralRelationProvider({
      organizationId: ORG,
      resolveActorPositions: () => [],
      positions,
      occupants,
      collegiateMemberships: memberships,
      evaluationResponsibilities: responsibilities,
      resolveEvaluationTarget,
    });
    const providers: PolicyEngineProviders = {
      identity: { isProfileActive: () => true, isMembershipActive: () => true },
      capabilities: { hasCapability: () => true },
      scopes: { getActiveScopes: () => ["ASSIGNED"] },
      targets: { resolveTargetTenant: () => ORG },
      relations: relation,
    };
    const req = (targetId: string) => ({
      actor: { actorId: "c_ger", organizationId: ORG },
      capability: "evaluation.write" as const,
      target: { type: "collaborator" as const, id: targetId },
      context: { date: new Date(), cycleId: "c1" },
      domainState: { allows: () => true },
    });
    expect(decidir(req("c_an1"), providers).allowed).toBe(true);
    const denied = decidir(req("c_an2"), providers);
    expect(denied.allowed).toBe(false);
    expect(denied.denial?.reason).toBe("SCOPE_INSUFFICIENT");
  });
});

describe("F4-04 — contrato capability × target (D18, fechado)", () => {
  it("permite combinações explicitamente suportadas", () => {
    expect(isCapabilityTargetCompatible("evaluation.write", { type: "evaluation", id: "x" })).toBe(true);
    expect(isCapabilityTargetCompatible("evaluation.write", { type: "collaborator", id: "x" })).toBe(true);
    expect(isCapabilityTargetCompatible("goal.write", { type: "goal", id: "x" })).toBe(true);
    expect(isCapabilityTargetCompatible("goal.write", { type: "collaborator", id: "x" })).toBe(true);
    expect(isCapabilityTargetCompatible("observation.create", { type: "cycle", id: "x" })).toBe(true);
    expect(isCapabilityTargetCompatible("report.view", { type: "evaluation", id: "x" })).toBe(true);
    expect(isCapabilityTargetCompatible("collaborator.create", { type: "collaborator", id: "x" })).toBe(true);
  });

  it("rejeita combinações semanticamente impossíveis", () => {
    expect(isCapabilityTargetCompatible("evaluation.write", { type: "goal", id: "x" })).toBe(false);
    expect(isCapabilityTargetCompatible("goal.write", { type: "evaluation", id: "x" })).toBe(false);
    expect(isCapabilityTargetCompatible("observation.create", { type: "goal", id: "x" })).toBe(false);
  });

  it("combinação não explicitamente autorizada => false (fail-closed)", () => {
    expect(isCapabilityTargetCompatible("settings.manage", { type: "collaborator", id: "x" })).toBe(false);
    expect(isCapabilityTargetCompatible("collaborator.create", { type: "cycle", id: "x" })).toBe(false);
    expect(isCapabilityTargetCompatible("report.view", { type: "goal", id: "x" })).toBe(false);
    expect(isCapabilityTargetCompatible("cycle.management.view", { type: "collaborator", id: "x" })).toBe(false);
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
