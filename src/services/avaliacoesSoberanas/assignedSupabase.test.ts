import { describe, expect, it } from "vitest";
import {
  criarDepsAssignedSupabase,
  mapearCiclosPorAnoNumero,
  responsabilidadeVigente,
} from "../../../supabase/functions/avaliacoes/assignedSupabase.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * F5-06 (Issue #103) — leituras soberanas do ASSIGNED (F3-08/F3-09) na Edge.
 *
 * Verifica o que NÃO pode dar errado: vigência da responsabilidade, tradução
 * (ano, ciclo) → UUID do ciclo (senão o alcance nunca casa com o alvo), alvo
 * avaliativo resolvido com o MESMO ciclo do ResourceContext e fail-closed em
 * qualquer ausência.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const CICLO_UUID = "55555555-5555-4555-8555-555555555555";
const AVALIACAO = "33333333-3333-4333-8333-333333333333";
const AVALIADO = "44444444-4444-4444-8444-444444444444";
const ATOR = "66666666-6666-4666-8666-666666666666";
const POSICAO = "77777777-7777-4777-8777-777777777777";
const SNAPSHOT = "88888888-8888-4888-8888-888888888888";

interface ResultadoFalso {
  readonly data: unknown;
  readonly error: unknown;
}

/**
 * Cliente falso: cada `.from(tabela)` devolve uma cadeia encadeável que resolve
 * com o resultado configurado para a tabela (tanto em `.order()` quanto ao ser
 * aguardada diretamente).
 */
function clienteFalso(porTabela: Record<string, ResultadoFalso>): SupabaseClient {
  const cadeia = (tabela: string) => {
    const resultado = porTabela[tabela] ?? { data: [], error: null };
    const no: Record<string, unknown> = {
      select: () => no,
      eq: () => no,
      in: () => no,
      order: () => Promise.resolve(resultado),
      maybeSingle: () => Promise.resolve(resultado),
      then: (
        resolver: (valor: ResultadoFalso) => unknown,
        rejeitar?: (erro: unknown) => unknown
      ) => Promise.resolve(resultado).then(resolver, rejeitar),
    };
    return no;
  };
  return { from: (tabela: string) => cadeia(tabela) } as unknown as SupabaseClient;
}

const AGORA = () => new Date("2026-02-01T00:00:00Z");

describe("leitura soberana do ASSIGNED (Edge)", () => {
  it("vigência da responsabilidade respeita valid_from/valid_to", () => {
    const ativa = { valid_from: "2026-01-01T00:00:00Z", valid_to: null };
    const futura = { valid_from: "2026-03-01T00:00:00Z", valid_to: null };
    const encerrada = { valid_from: "2025-01-01T00:00:00Z", valid_to: "2026-01-15T00:00:00Z" };

    expect(responsabilidadeVigente(ativa, "2026-02-01T00:00:00Z")).toBe(true);
    expect(responsabilidadeVigente(futura, "2026-02-01T00:00:00Z")).toBe(false);
    expect(responsabilidadeVigente(encerrada, "2026-02-01T00:00:00Z")).toBe(false);
    // Instante inválido ⇒ fail-closed.
    expect(responsabilidadeVigente(ativa, "data-invalida")).toBe(false);
    expect(
      responsabilidadeVigente({ valid_from: "x", valid_to: null }, "2026-02-01T00:00:00Z")
    ).toBe(false);
  });

  it("mapeia (ano, ciclo) para o UUID do ciclo do tenant", () => {
    const mapa = mapearCiclosPorAnoNumero([
      { id: CICLO_UUID, organization_id: ORG, ano: 2026, numero: 1 },
    ]);
    expect(mapa.get("2026|1")).toBe(CICLO_UUID);
    expect(mapa.get("2026|2")).toBeUndefined();
  });

  it("colegiado do ator usa o UUID do ciclo (F3-08 traduzido)", async () => {
    const admin = clienteFalso({
      collegiate_cycle_snapshot_members: {
        data: [{ snapshot_id: SNAPSHOT, organization_id: ORG, member_collaborator_id: ATOR }],
        error: null,
      },
      collegiate_cycle_snapshots: {
        data: [
          {
            id: SNAPSHOT,
            organization_id: ORG,
            ano: 2026,
            ciclo: 1,
            collaborator_id: AVALIADO,
          },
        ],
        error: null,
      },
      evaluation_cycles: {
        data: [{ id: CICLO_UUID, organization_id: ORG, ano: 2026, numero: 1 }],
        error: null,
      },
    });

    const deps = criarDepsAssignedSupabase(admin, AGORA);
    const linhas = await deps.listarColegiado(ATOR, ORG);

    expect(linhas).toEqual([
      {
        cycleId: CICLO_UUID,
        organizationId: ORG,
        evaluatedCollaboratorId: AVALIADO,
        memberCollaboratorId: ATOR,
      },
    ]);
  });

  it("sem snapshot correspondente a ciclo do tenant, o colegiado é vazio (fail-closed)", async () => {
    const admin = clienteFalso({
      collegiate_cycle_snapshot_members: {
        data: [{ snapshot_id: SNAPSHOT, organization_id: ORG, member_collaborator_id: ATOR }],
        error: null,
      },
      collegiate_cycle_snapshots: {
        data: [{ id: SNAPSHOT, organization_id: ORG, ano: 2026, ciclo: 3, collaborator_id: AVALIADO }],
        error: null,
      },
      evaluation_cycles: {
        data: [{ id: CICLO_UUID, organization_id: ORG, ano: 2026, numero: 1 }],
        error: null,
      },
    });

    const linhas = await criarDepsAssignedSupabase(admin, AGORA).listarColegiado(ATOR, ORG);
    expect(linhas).toEqual([]);
  });

  it("responsabilidade VIGENTE vira EvaluationResponsibility com o UUID do ciclo", async () => {
    const admin = clienteFalso({
      cycle_evaluation_responsibilities: {
        data: [
          {
            snapshot_id: SNAPSHOT,
            organization_id: ORG,
            position_id: POSICAO,
            responsible_collaborator_id: ATOR,
            valid_from: "2026-01-01T00:00:00Z",
            valid_to: null,
          },
          {
            snapshot_id: SNAPSHOT,
            organization_id: ORG,
            position_id: "outra",
            responsible_collaborator_id: ATOR,
            valid_from: "2026-01-01T00:00:00Z",
            valid_to: "2026-01-15T00:00:00Z",
          },
        ],
        error: null,
      },
      collegiate_cycle_snapshots: {
        data: [
          { id: SNAPSHOT, organization_id: ORG, ano: 2026, ciclo: 1, collaborator_id: AVALIADO },
        ],
        error: null,
      },
      evaluation_cycles: {
        data: [{ id: CICLO_UUID, organization_id: ORG, ano: 2026, numero: 1 }],
        error: null,
      },
    });

    const linhas = await criarDepsAssignedSupabase(admin, AGORA).listarResponsabilidades(ATOR, ORG);

    // Somente a vigente entra, e com o ciclo em UUID.
    expect(linhas).toHaveLength(1);
    expect(linhas[0]).toEqual({
      cycleId: CICLO_UUID,
      organizationId: ORG,
      evaluatedCollaboratorId: AVALIADO,
      positionId: POSICAO,
      responsibleCollaboratorId: ATOR,
    });
  });

  it("resolver do alvo devolve o MESMO ciclo do ResourceContext", async () => {
    const admin = clienteFalso({
      evaluations: {
        data: {
          id: AVALIACAO,
          organization_id: ORG,
          cycle_id: CICLO_UUID,
          evaluated_collaborator_id: AVALIADO,
        },
        error: null,
      },
      evaluation_cycles: {
        data: { id: CICLO_UUID, organization_id: ORG, ano: 2026, numero: 1 },
        error: null,
      },
      collegiate_cycle_snapshots: {
        data: {
          id: SNAPSHOT,
          organization_id: ORG,
          ano: 2026,
          ciclo: 1,
          collaborator_id: AVALIADO,
        },
        error: null,
      },
      collegiate_cycle_snapshot_positions: {
        data: [
          {
            snapshot_id: SNAPSHOT,
            organization_id: ORG,
            position_id: POSICAO,
            superior_position_id: null,
          },
        ],
        error: null,
      },
    });

    const alvo = await criarDepsAssignedSupabase(admin, AGORA).resolverAlvoAvaliativo({
      target: { type: "evaluation", id: AVALIACAO },
      cycleId: CICLO_UUID,
      organizationId: ORG,
    });

    expect(alvo).toEqual({
      cycleId: CICLO_UUID,
      organizationId: ORG,
      evaluatedCollaboratorId: AVALIADO,
      positionId: POSICAO,
    });
  });

  it("ciclo divergente, tenant divergente ou alvo não-avaliação ⇒ null (fail-closed)", async () => {
    const admin = clienteFalso({
      evaluations: {
        data: {
          id: AVALIACAO,
          organization_id: ORG,
          cycle_id: CICLO_UUID,
          evaluated_collaborator_id: AVALIADO,
        },
        error: null,
      },
    });
    const deps = criarDepsAssignedSupabase(admin, AGORA);

    expect(
      await deps.resolverAlvoAvaliativo({
        target: { type: "evaluation", id: AVALIACAO },
        cycleId: "outro-ciclo",
        organizationId: ORG,
      })
    ).toBeNull();

    expect(
      await deps.resolverAlvoAvaliativo({
        target: { type: "collaborator", id: AVALIADO },
        cycleId: CICLO_UUID,
        organizationId: ORG,
      })
    ).toBeNull();

    const semCiclo = await criarDepsAssignedSupabase(
      clienteFalso({ evaluations: { data: null, error: { message: "sem tenant" } } }),
      AGORA
    ).resolverAlvoAvaliativo({
      target: { type: "evaluation", id: AVALIACAO },
      cycleId: CICLO_UUID,
      organizationId: ORG_B,
    });
    expect(semCiclo).toBeNull();
  });
});
