/**
 * F5-06 (Issue #103) — consultas soberanas do ASSIGNED (F3-08/F3-09).
 *
 * Descritores puros das consultas usadas pela fronteira confiável para
 * materializar membros de colegiado e responsáveis avaliativos do ator. Ficam
 * isolados aqui para poderem ser verificados por teste (tabelas e filtros
 * exatos) sem executar I/O: a Edge Function apenas executa o descritor no
 * cliente privilegiado.
 *
 * Invariantes de segurança:
 * - TODA consulta é filtrada por `organization_id` (tenant nunca vem do cliente);
 * - nenhuma consulta lê cargo/função/senioridade (D16/D17);
 * - `cycle_evaluation_responsibilities` considera apenas linhas VIGENTES na data.
 */

export interface DescritorConsulta {
  readonly tabela: string;
  readonly colunas: readonly string[];
  readonly filtros: Readonly<Record<string, string>>;
  readonly filtrosNaoNulos?: readonly string[];
  readonly ordenacao?: readonly string[];
  readonly limite?: number;
}

/** Colegiado CONGELADO do ator no ciclo (F3-08), por snapshot do avaliado. */
export function consultaColegiadoDoAtor(entrada: {
  readonly organizationId: string;
  readonly cycleId: string;
}): {
  readonly snapshots: DescritorConsulta;
  readonly membros: DescritorConsulta;
} {
  return {
    snapshots: {
      tabela: "collegiate_cycle_snapshots",
      colunas: ["id", "organization_id", "ano", "ciclo"],
      filtros: { organization_id: entrada.organizationId },
    },
    membros: {
      tabela: "collegiate_cycle_snapshot_members",
      colunas: ["snapshot_id", "organization_id", "member_collaborator_id"],
      filtros: { organization_id: entrada.organizationId },
    },
  };
}

/** Responsabilidade avaliativa vigente (F3-09) — titular já com sucessão aplicada. */
export function consultaResponsabilidadesVigentes(entrada: {
  readonly organizationId: string;
  readonly instanteIso: string;
}): DescritorConsulta {
  return {
    tabela: "cycle_evaluation_responsibilities",
    colunas: [
      "snapshot_id",
      "organization_id",
      "position_id",
      "responsible_collaborator_id",
      "valid_from",
      "valid_to",
    ],
    filtros: { organization_id: entrada.organizationId },
    ordenacao: ["snapshot_id", "position_id"],
  };
}

/** Ciclo soberano da avaliação (para resolver o snapshot do avaliado). */
export function consultaCicloDaAvaliacao(entrada: {
  readonly organizationId: string;
  readonly cycleId: string;
}): DescritorConsulta {
  return {
    tabela: "evaluation_cycles",
    colunas: ["id", "organization_id", "ano", "numero", "config_version_id", "status"],
    filtros: { id: entrada.cycleId, organization_id: entrada.organizationId },
    limite: 1,
  };
}

/** Snapshot F3-08 do AVALIADO no ciclo, com a posição ocupada. */
export function consultaSnapshotDoAvaliado(entrada: {
  readonly organizationId: string;
  readonly ano: number;
  readonly ciclo: number;
  readonly evaluatedCollaboratorId: string;
}): {
  readonly snapshot: DescritorConsulta;
  readonly posicoes: DescritorConsulta;
} {
  return {
    snapshot: {
      tabela: "collegiate_cycle_snapshots",
      colunas: ["id", "organization_id", "collaborator_id"],
      filtros: {
        organization_id: entrada.organizationId,
        ano: String(entrada.ano),
        ciclo: String(entrada.ciclo),
        collaborator_id: entrada.evaluatedCollaboratorId,
      },
      limite: 1,
    },
    posicoes: {
      tabela: "collegiate_cycle_snapshot_positions",
      colunas: ["snapshot_id", "organization_id", "position_id", "superior_position_id"],
      filtros: { organization_id: entrada.organizationId },
      ordenacao: ["position_id"],
    },
  };
}

/** Colegiado congelado de UM avaliado (para o snapshot do alvo avaliativo). */
export function consultaMembrosDoSnapshot(entrada: {
  readonly organizationId: string;
  readonly snapshotId: string;
}): DescritorConsulta {
  return {
    tabela: "collegiate_cycle_snapshot_members",
    colunas: ["snapshot_id", "organization_id", "member_collaborator_id"],
    filtros: {
      snapshot_id: entrada.snapshotId,
      organization_id: entrada.organizationId,
    },
  };
}
