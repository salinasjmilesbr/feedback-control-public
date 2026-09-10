import { describe, expect, it } from "vitest";
import {
  carregarDadosAssignedAvaliacoes,
  criarResolvedorAlvoAvaliativo,
  type DepsAssignedAvaliacoes,
} from "./assignedSoberano.ts";
import {
  isCollegiateAssigned,
  isEvaluationAssigned,
} from "../../authorization/providers/assigned.ts";

/**
 * F5-06 (Issue #103) — ASSIGNED soberano (F3-08/F3-09): membro de colegiado e
 * responsável avaliativo alcançam a avaliação; alvo não resolvido, tenant
 * divergente e ciclo divergente negam (fail-closed).
 */

const ORG = "org-1";
const ORG_B = "org-2";
const CICLO = "ciclo-1";
const AVALIACAO = "eval-1";
const AVALIADO = "col-avaliado";
const MEMBRO = "col-membro";
const RESPONSAVEL = "col-responsavel";
const POSICAO = "pos-1";

function deps(parcial: Partial<DepsAssignedAvaliacoes> = {}): DepsAssignedAvaliacoes {
  return {
    listarColegiado: async () => [
      {
        cycleId: CICLO,
        organizationId: ORG,
        evaluatedCollaboratorId: AVALIADO,
        memberCollaboratorId: MEMBRO,
      },
    ],
    listarResponsabilidades: async () => [
      {
        cycleId: CICLO,
        organizationId: ORG,
        evaluatedCollaboratorId: AVALIADO,
        positionId: POSICAO,
        responsibleCollaboratorId: RESPONSAVEL,
      },
    ],
    resolverAlvoAvaliativo: async () => ({
      cycleId: CICLO,
      organizationId: ORG,
      evaluatedCollaboratorId: AVALIADO,
      positionId: POSICAO,
    }),
    ...parcial,
  };
}

describe("ASSIGNED soberano das avaliações", () => {
  it("membro de colegiado recebe ASSIGNED; quem não é membro não recebe", async () => {
    const dados = await carregarDadosAssignedAvaliacoes(
      {
        actorCollaboratorId: MEMBRO,
        organizationId: ORG,
        target: { type: "evaluation", id: AVALIACAO },
        cycleId: CICLO,
      },
      deps()
    );

    expect(dados).not.toBeNull();
    const alvo = dados!.resolveEvaluationTarget(
      { type: "evaluation", id: AVALIACAO },
      CICLO,
      ORG
    );
    expect(alvo).toEqual({
      cycleId: CICLO,
      organizationId: ORG,
      evaluatedCollaboratorId: AVALIADO,
      positionId: POSICAO,
    });
    expect(isCollegiateAssigned(MEMBRO, alvo!, dados!.collegiateMemberships)).toBe(true);
    expect(isEvaluationAssigned(MEMBRO, alvo!, dados!.evaluationResponsibilities)).toBe(
      false
    );
  });

  it("responsável avaliativo recebe ASSIGNED pela responsabilidade (F3-09)", async () => {
    const dados = await carregarDadosAssignedAvaliacoes(
      {
        actorCollaboratorId: RESPONSAVEL,
        organizationId: ORG,
        target: { type: "evaluation", id: AVALIACAO },
        cycleId: CICLO,
      },
      deps()
    );

    const alvo = dados!.resolveEvaluationTarget(
      { type: "evaluation", id: AVALIACAO },
      CICLO,
      ORG
    );
    expect(isEvaluationAssigned(RESPONSAVEL, alvo!, dados!.evaluationResponsibilities)).toBe(
      true
    );
    expect(isCollegiateAssigned(RESPONSAVEL, alvo!, dados!.collegiateMemberships)).toBe(
      false
    );
  });

  it("ATOR SEM vínculo de colaborador ⇒ sem ASSIGNED (null)", async () => {
    const dados = await carregarDadosAssignedAvaliacoes(
      {
        actorCollaboratorId: null,
        organizationId: ORG,
        target: { type: "evaluation", id: AVALIACAO },
        cycleId: CICLO,
      },
      deps()
    );
    expect(dados).toBeNull();
  });

  it("alvo NÃO resolvido em fonte soberana ⇒ ASSIGNED nega (fail-closed)", async () => {
    const dados = await carregarDadosAssignedAvaliacoes(
      {
        actorCollaboratorId: MEMBRO,
        organizationId: ORG,
        target: { type: "evaluation", id: AVALIACAO },
        cycleId: CICLO,
      },
      deps({ resolverAlvoAvaliativo: async () => null })
    );

    expect(
      dados!.resolveEvaluationTarget({ type: "evaluation", id: AVALIACAO }, CICLO, ORG)
    ).toBeUndefined();
  });

  it("resolvedor só responde ao ALVO da operação: outro id/ciclo/tenant ⇒ undefined", async () => {
    const dados = await carregarDadosAssignedAvaliacoes(
      {
        actorCollaboratorId: MEMBRO,
        organizationId: ORG,
        target: { type: "evaluation", id: AVALIACAO },
        cycleId: CICLO,
      },
      deps()
    );
    const resolver = dados!.resolveEvaluationTarget;

    expect(resolver({ type: "evaluation", id: "outra" }, CICLO, ORG)).toBeUndefined();
    expect(resolver({ type: "evaluation", id: AVALIACAO }, "outro-ciclo", ORG)).toBeUndefined();
    expect(resolver({ type: "evaluation", id: AVALIACAO }, CICLO, ORG_B)).toBeUndefined();
    expect(resolver({ type: "evaluation", id: AVALIACAO }, undefined, ORG)).toBeUndefined();
    expect(resolver({ type: "collaborator", id: AVALIADO }, CICLO, ORG)).toBeUndefined();
  });

  it("resolvedor construído sem alvo pré-resolvido nunca responde", () => {
    const resolver = criarResolvedorAlvoAvaliativo(null);
    expect(resolver({ type: "evaluation", id: AVALIACAO }, CICLO, ORG)).toBeUndefined();
  });

  it("alvo pré-resolvido sem tipo evaluation não vira ASSIGNED (fail-closed)", async () => {
    const dados = await carregarDadosAssignedAvaliacoes(
      {
        actorCollaboratorId: MEMBRO,
        organizationId: ORG,
        target: { type: "collaborator", id: AVALIADO },
        cycleId: CICLO,
      },
      deps()
    );
    expect(
      dados!.resolveEvaluationTarget({ type: "evaluation", id: AVALIACAO }, CICLO, ORG)
    ).toBeUndefined();
  });
});
