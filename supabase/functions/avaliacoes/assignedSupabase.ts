/**
 * F5-06 (Issue #103) — ASSIGNED soberano a partir do PostgreSQL (Edge).
 *
 * Implementa as leituras de `consultasAssigned.ts` no cliente PRIVILEGIADO
 * (service_role) da fronteira confiável. Toda leitura é filtrada por
 * `organization_id` (tenant nunca vem do cliente) e nenhuma coluna de
 * cargo/função/senioridade é tocada (D16/D17).
 *
 * IDENTIFICADOR DE CICLO: o `cycleId` usado pelo Policy Engine é o **UUID** de
 * `evaluation_cycles.id` (o mesmo que o ResourceContext expõe). O snapshot F3-08
 * identifica o ciclo por `(ano, ciclo)`, então cada snapshot é traduzido para o
 * UUID do ciclo do tenant antes de virar `CollegiateMembership` /
 * `EvaluationResponsibility` — sem isso o alcance ASSIGNED nunca casaria com o
 * alvo.
 *
 * LIMITE CONHECIDO (registrado): um avaliado pode ter mais de uma posição na
 * cadeia. Sem vínculo explícito posição→responsável no modelo atual, o alvo é
 * resolvido pela PRIMEIRA posição da cadeia (ordenada). Ponta ambígua ⇒ alvo não
 * resolvido ⇒ ASSIGNED nega (fail-closed).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  carregarDadosAssignedAvaliacoes,
  type DepsAssignedAvaliacoes,
  type LinhaAlvoAvaliativoSoberana,
  type LinhaColegiadoSoberana,
  type LinhaResponsabilidadeSoberana,
} from "../../../src/services/avaliacoesSoberanas/assignedSoberano.ts";
import type { TargetRef } from "../../../src/authorization/policyEngine/types.ts";

interface LinhaSnapshot {
  id: string;
  organization_id: string;
  ano: number;
  ciclo: number;
  collaborator_id: string;
}

interface LinhaMembro {
  snapshot_id: string;
  organization_id: string;
  member_collaborator_id: string;
}

interface LinhaResponsabilidade {
  snapshot_id: string;
  organization_id: string;
  position_id: string;
  responsible_collaborator_id: string;
  valid_from: string;
  valid_to: string | null;
}

interface LinhaPosicaoSnapshot {
  snapshot_id: string;
  organization_id: string;
  position_id: string;
  superior_position_id: string | null;
}

interface LinhaAvaliacao {
  id: string;
  organization_id: string;
  cycle_id: string;
  evaluated_collaborator_id: string;
}

interface LinhaCiclo {
  id: string;
  organization_id: string;
  ano: number;
  numero: number;
}

/** Verdadeiro quando a responsabilidade está vigente no instante informado. */
export function responsabilidadeVigente(
  linha: { readonly valid_from: string; readonly valid_to: string | null },
  instanteIso: string
): boolean {
  const instante = Date.parse(instanteIso);
  if (!Number.isFinite(instante)) return false;
  const inicio = Date.parse(linha.valid_from);
  if (!Number.isFinite(inicio) || inicio > instante) return false;
  if (linha.valid_to === null) return true;
  const fim = Date.parse(linha.valid_to);
  return Number.isFinite(fim) ? fim > instante : false;
}

/** Chave (ano, ciclo) → UUID do ciclo do tenant. */
export function mapearCiclosPorAnoNumero(
  ciclos: readonly LinhaCiclo[]
): ReadonlyMap<string, string> {
  return new Map(ciclos.map((ciclo) => [`${ciclo.ano}|${ciclo.numero}`, ciclo.id]));
}

export function criarDepsAssignedSupabase(
  admin: SupabaseClient,
  agora: () => Date
): DepsAssignedAvaliacoes {
  /** Todos os ciclos do tenant com os respectivos UUIDs (traduz snapshots). */
  async function ciclosDoTenant(organizationId: string): Promise<readonly LinhaCiclo[]> {
    const { data, error } = await admin
      .from("evaluation_cycles")
      .select("id, organization_id, ano, numero")
      .eq("organization_id", organizationId);
    if (error || !data) return [];
    return data as LinhaCiclo[];
  }

  async function colegiadoDoAtor(
    actorCollaboratorId: string,
    organizationId: string
  ): Promise<readonly LinhaColegiadoSoberana[]> {
    const { data: membros, error: erroMembros } = await admin
      .from("collegiate_cycle_snapshot_members")
      .select("snapshot_id, organization_id, member_collaborator_id")
      .eq("organization_id", organizationId)
      .eq("member_collaborator_id", actorCollaboratorId);
    if (erroMembros || !membros || membros.length === 0) return [];

    const idsSnapshots = (membros as LinhaMembro[]).map((linha) => linha.snapshot_id);
    const { data: snapshots, error: erroSnapshots } = await admin
      .from("collegiate_cycle_snapshots")
      .select("id, organization_id, ano, ciclo, collaborator_id")
      .eq("organization_id", organizationId)
      .in("id", idsSnapshots);
    if (erroSnapshots || !snapshots) return [];

    const mapaCiclos = mapearCiclosPorAnoNumero(await ciclosDoTenant(organizationId));

    return (snapshots as LinhaSnapshot[]).flatMap((snapshot) => {
      const cycleId = mapaCiclos.get(`${snapshot.ano}|${snapshot.ciclo}`);
      if (!cycleId) return [];
      return [
        {
          cycleId,
          organizationId: snapshot.organization_id,
          evaluatedCollaboratorId: snapshot.collaborator_id,
          memberCollaboratorId: actorCollaboratorId,
        },
      ];
    });
  }

  async function responsabilidadesDoAtor(
    actorCollaboratorId: string,
    organizationId: string
  ): Promise<readonly LinhaResponsabilidadeSoberana[]> {
    const { data, error } = await admin
      .from("cycle_evaluation_responsibilities")
      .select(
        "snapshot_id, organization_id, position_id, responsible_collaborator_id, valid_from, valid_to"
      )
      .eq("organization_id", organizationId)
      .eq("responsible_collaborator_id", actorCollaboratorId);
    if (error || !data) return [];

    const instanteIso = agora().toISOString();
    const vigentes = (data as LinhaResponsabilidade[]).filter((linha) =>
      responsabilidadeVigente(linha, instanteIso)
    );
    if (vigentes.length === 0) return [];

    const idsSnapshots = [...new Set(vigentes.map((linha) => linha.snapshot_id))];
    const { data: snapshots, error: erroSnapshots } = await admin
      .from("collegiate_cycle_snapshots")
      .select("id, organization_id, ano, ciclo, collaborator_id")
      .eq("organization_id", organizationId)
      .in("id", idsSnapshots);
    if (erroSnapshots || !snapshots) return [];

    const porSnapshot = new Map(
      (snapshots as LinhaSnapshot[]).map((snapshot) => [snapshot.id, snapshot])
    );
    const mapaCiclos = mapearCiclosPorAnoNumero(await ciclosDoTenant(organizationId));

    return vigentes.flatMap((linha) => {
      const snapshot = porSnapshot.get(linha.snapshot_id);
      if (!snapshot) return [];
      const cycleId = mapaCiclos.get(`${snapshot.ano}|${snapshot.ciclo}`);
      if (!cycleId) return [];
      return [
        {
          cycleId,
          organizationId: linha.organization_id,
          evaluatedCollaboratorId: snapshot.collaborator_id,
          positionId: linha.position_id,
          responsibleCollaboratorId: linha.responsible_collaborator_id,
        },
      ];
    });
  }

  async function resolverAlvo(entrada: {
    readonly target: TargetRef;
    readonly cycleId: string | undefined;
    readonly organizationId: string;
  }): Promise<LinhaAlvoAvaliativoSoberana | null> {
    if (entrada.target.type !== "evaluation" || !entrada.cycleId) return null;

    const { data: avaliacao, error: erroAvaliacao } = await admin
      .from("evaluations")
      .select("id, organization_id, cycle_id, evaluated_collaborator_id")
      .eq("id", entrada.target.id)
      .eq("organization_id", entrada.organizationId)
      .maybeSingle();
    if (erroAvaliacao || !avaliacao) return null;
    const linhaAvaliacao = avaliacao as LinhaAvaliacao;

    // O ciclo do alvo precisa ser o MESMO recurso exposto pelo ResourceContext.
    if (linhaAvaliacao.cycle_id !== entrada.cycleId) return null;

    const { data: ciclo, error: erroCiclo } = await admin
      .from("evaluation_cycles")
      .select("id, organization_id, ano, numero")
      .eq("id", linhaAvaliacao.cycle_id)
      .eq("organization_id", entrada.organizationId)
      .maybeSingle();
    if (erroCiclo || !ciclo) return null;
    const linhaCiclo = ciclo as LinhaCiclo;

    const { data: snapshot, error: erroSnapshot } = await admin
      .from("collegiate_cycle_snapshots")
      .select("id, organization_id, ano, ciclo, collaborator_id")
      .eq("organization_id", entrada.organizationId)
      .eq("ano", linhaCiclo.ano)
      .eq("ciclo", linhaCiclo.numero)
      .eq("collaborator_id", linhaAvaliacao.evaluated_collaborator_id)
      .maybeSingle();
    if (erroSnapshot || !snapshot) return null;
    const linhaSnapshot = snapshot as LinhaSnapshot;

    const { data: posicoes, error: erroPosicoes } = await admin
      .from("collegiate_cycle_snapshot_positions")
      .select("snapshot_id, organization_id, position_id, superior_position_id")
      .eq("snapshot_id", linhaSnapshot.id)
      .eq("organization_id", entrada.organizationId)
      .order("position_id", { ascending: true });
    if (erroPosicoes || !posicoes || posicoes.length === 0) return null;

    const primeira = (posicoes as LinhaPosicaoSnapshot[])[0]!;
    return {
      cycleId: linhaAvaliacao.cycle_id,
      organizationId: entrada.organizationId,
      evaluatedCollaboratorId: linhaAvaliacao.evaluated_collaborator_id,
      positionId: primeira.position_id,
    };
  }

  return {
    listarColegiado: colegiadoDoAtor,
    listarResponsabilidades: responsabilidadesDoAtor,
    resolverAlvoAvaliativo: resolverAlvo,
  };
}

/** Carrega o bloco ASSIGNED da operação corrente (ou `null` quando não há). */
export async function carregarAssignedDaOperacao(
  admin: SupabaseClient,
  entrada: {
    readonly collaboratorId: string | null;
    readonly organizationId: string;
    readonly target: TargetRef;
    readonly cycleId: string | undefined;
    readonly agora: () => Date;
  }
) {
  return carregarDadosAssignedAvaliacoes(
    {
      actorCollaboratorId: entrada.collaboratorId,
      organizationId: entrada.organizationId,
      target: entrada.target,
      cycleId: entrada.cycleId,
    },
    criarDepsAssignedSupabase(admin, entrada.agora)
  );
}
