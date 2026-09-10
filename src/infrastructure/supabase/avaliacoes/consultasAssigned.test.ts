import { describe, expect, it } from "vitest";
import {
  consultaCicloDaAvaliacao,
  consultaColegiadoDoAtor,
  consultaMembrosDoSnapshot,
  consultaResponsabilidadesVigentes,
  consultaSnapshotDoAvaliado,
  type DescritorConsulta,
} from "./consultasAssigned.ts";

/**
 * F5-06 (Issue #103) — descritores das consultas do ASSIGNED: tenant sempre
 * presente, apenas tabelas F3-08/F3-09 envolvidas e nenhuma leitura de cargo,
 * função ou senioridade (D16/D17).
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "55555555-5555-4555-8555-555555555555";
const AVALIADO = "44444444-4444-4444-8444-444444444444";
const SNAPSHOT = "66666666-6666-4666-8666-666666666666";

function descritores(): readonly DescritorConsulta[] {
  const colegiado = consultaColegiadoDoAtor({ organizationId: ORG, cycleId: CICLO });
  const snapshot = consultaSnapshotDoAvaliado({
    organizationId: ORG,
    ano: 2026,
    ciclo: 1,
    evaluatedCollaboratorId: AVALIADO,
  });
  return [
    colegiado.snapshots,
    colegiado.membros,
    consultaResponsabilidadesVigentes({ organizationId: ORG, instanteIso: "2026-02-01T00:00:00Z" }),
    consultaCicloDaAvaliacao({ organizationId: ORG, cycleId: CICLO }),
    snapshot.snapshot,
    snapshot.posicoes,
    consultaMembrosDoSnapshot({ organizationId: ORG, snapshotId: SNAPSHOT }),
  ];
}

describe("consultas soberanas do ASSIGNED", () => {
  it("TODA consulta é filtrada pelo tenant (organization_id)", () => {
    for (const descritor of descritores()) {
      expect(descritor.filtros.organization_id).toBe(ORG);
    }
  });

  it("usa somente tabelas do ciclo/avaliação (nenhuma tabela de cargo)", () => {
    const proibidas = ["job_roles", "seniority_levels", "collaborators"];
    for (const descritor of descritores()) {
      expect(proibidas).not.toContain(descritor.tabela);
      expect(descritor.tabela).toMatch(/^(collegiate_cycle_snapshot|cycle_evaluation_resp|evaluation_cycles)/);
    }
  });

  it("nenhuma coluna lida é de cargo/função/senioridade", () => {
    const proibidas = ["funcao", "cargo", "job_role", "job_role_id", "seniority", "seniority_id"];
    for (const descritor of descritores()) {
      for (const coluna of descritor.colunas) {
        expect(proibidas).not.toContain(coluna);
      }
    }
  });

  it("responsabilidades avaliativas são lidas com vigência (valid_from/valid_to)", () => {
    const descritor = consultaResponsabilidadesVigentes({
      organizationId: ORG,
      instanteIso: "2026-02-01T00:00:00Z",
    });
    expect(descritor.colunas).toContain("valid_from");
    expect(descritor.colunas).toContain("valid_to");
    expect(descritor.tabela).toBe("cycle_evaluation_responsibilities");
  });

  it("snapshot do avaliado é localizado por ano/ciclo/colaborador (F3-08)", () => {
    const { snapshot } = consultaSnapshotDoAvaliado({
      organizationId: ORG,
      ano: 2026,
      ciclo: 2,
      evaluatedCollaboratorId: AVALIADO,
    });
    expect(snapshot.filtros).toMatchObject({
      organization_id: ORG,
      ano: "2026",
      ciclo: "2",
      collaborator_id: AVALIADO,
    });
    expect(snapshot.limite).toBe(1);
  });

  it("membros do snapshot filtram por snapshot e tenant (sem vazar outro snapshot)", () => {
    const membros = consultaMembrosDoSnapshot({ organizationId: ORG, snapshotId: SNAPSHOT });
    expect(membros.filtros).toEqual({ snapshot_id: SNAPSHOT, organization_id: ORG });
  });

  it("ciclo é lido com o filtro de tenant e limite de uma linha", () => {
    const ciclo = consultaCicloDaAvaliacao({ organizationId: ORG, cycleId: CICLO });
    expect(ciclo.filtros).toEqual({ id: CICLO, organization_id: ORG });
    expect(ciclo.limite).toBe(1);
  });
});
