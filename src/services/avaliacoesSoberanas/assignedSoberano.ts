/**
 * F5-06 (Issue #103) — ASSIGNED soberano para avaliações (F3-08/F3-09).
 *
 * O escopo `ASSIGNED` NÃO é resolvido pelo RPC genérico de escopos (ele devolve
 * vazio de propósito — ver F4-02). Ele precisa ser derivado das fontes
 * soberanas do ciclo:
 *
 *   - membro de COLEGIADO     ← collegiate_cycle_snapshot_members (F3-08)
 *   - responsável avaliativo  ← cycle_evaluation_responsibilities + sucessão (F3-09)
 *
 * Estrutura em duas etapas, porque o Policy Engine é SÍNCRONO:
 *   1. `carregarDadosAssignedAvaliacoes` faz as leituras (assíncronas, injetadas)
 *      e materializa o alvo avaliativo da operação;
 *   2. `criarResolvedorAlvoAvaliativo` devolve o resolvedor SÍNCRONO consumido
 *      pelo `RelationProvider` (`EvaluationTargetResolver`).
 *
 * Nenhuma capability/scope/tenant é decidida aqui: o módulo apenas materializa
 * os dados soberanos do ator para o engine. Tudo é fail-closed: alvo não
 * resolvido ⇒ `undefined` ⇒ ASSIGNED nega.
 */

import type {
  CollegiateMembership,
  EvaluationResponsibility,
  EvaluationTarget,
  EvaluationTargetResolver,
} from "../../authorization/providers/assigned.ts";
import type { TargetRef } from "../../authorization/policyEngine/types.ts";

/** Linhas soberanas (formato das tabelas F3-08/F3-09). */
export interface LinhaColegiadoSoberana {
  readonly cycleId: string;
  readonly organizationId: string;
  readonly evaluatedCollaboratorId: string;
  readonly memberCollaboratorId: string;
}

export interface LinhaResponsabilidadeSoberana {
  readonly cycleId: string;
  readonly organizationId: string;
  readonly evaluatedCollaboratorId: string;
  readonly positionId: string;
  readonly responsibleCollaboratorId: string;
}

export interface LinhaAlvoAvaliativoSoberana {
  readonly cycleId: string;
  readonly organizationId: string;
  readonly evaluatedCollaboratorId: string;
  readonly positionId: string;
}

export interface EntradaResolverAlvoAvaliativo {
  readonly target: TargetRef;
  readonly cycleId: string | undefined;
  readonly organizationId: string;
}

export interface DepsAssignedAvaliacoes {
  /** Colegiado congelado do ator no ciclo (F3-08). */
  listarColegiado(
    actorCollaboratorId: string,
    organizationId: string
  ): Promise<readonly LinhaColegiadoSoberana[]>;
  /** Responsabilidades avaliativas vigentes do ator (F3-09, titular + sucessão). */
  listarResponsabilidades(
    actorCollaboratorId: string,
    organizationId: string
  ): Promise<readonly LinhaResponsabilidadeSoberana[]>;
  /**
   * Resolve o par (avaliado, posição) do alvo avaliativo. Devolve `null` quando
   * não é possível resolver com as fontes soberanas (fail-closed).
   */
  resolverAlvoAvaliativo(
    entrada: EntradaResolverAlvoAvaliativo
  ): Promise<LinhaAlvoAvaliativoSoberana | null>;
}

export interface DadosAssignedAvaliacoes {
  readonly collegiateMemberships: readonly CollegiateMembership[];
  readonly evaluationResponsibilities: readonly EvaluationResponsibility[];
  readonly resolveEvaluationTarget: EvaluationTargetResolver;
}

/** Chave estável do alvo avaliativo pré-resolvido. */
function chaveAlvo(evaluationId: string, cycleId: string, organizationId: string): string {
  return `${evaluationId}|${cycleId}|${organizationId}`;
}

/**
 * Resolvedor SÍNCRONO do engine a partir do alvo pré-resolvido. Só responde para
 * exatamente o alvo da operação (tipo `evaluation`, mesmo id, mesmo ciclo e
 * mesmo tenant) — qualquer outro alvo devolve `undefined` (fail-closed).
 */
export function criarResolvedorAlvoAvaliativo(
  alvoPreResolvido: {
    readonly evaluationId: string;
    readonly linha: LinhaAlvoAvaliativoSoberana;
  } | null
): EvaluationTargetResolver {
  if (!alvoPreResolvido) return () => undefined;
  const chave = chaveAlvo(
    alvoPreResolvido.evaluationId,
    alvoPreResolvido.linha.cycleId,
    alvoPreResolvido.linha.organizationId
  );
  const alvo: EvaluationTarget = {
    cycleId: alvoPreResolvido.linha.cycleId,
    organizationId: alvoPreResolvido.linha.organizationId,
    evaluatedCollaboratorId: alvoPreResolvido.linha.evaluatedCollaboratorId,
    positionId: alvoPreResolvido.linha.positionId,
  };

  return (target, cycleId, organizationId) => {
    if (target.type !== "evaluation") return undefined;
    if (!cycleId) return undefined;
    return chaveAlvo(target.id, cycleId, organizationId) === chave ? alvo : undefined;
  };
}

/**
 * Carrega os dados soberanos do ASSIGNED para a operação corrente. Sem vínculo
 * de colaborador (ADMIN sem collaborator) devolve `null` — não há ASSIGNED.
 */
export async function carregarDadosAssignedAvaliacoes(
  entrada: {
    readonly actorCollaboratorId: string | null;
    readonly organizationId: string;
    readonly target: TargetRef;
    readonly cycleId: string | undefined;
  },
  deps: DepsAssignedAvaliacoes
): Promise<DadosAssignedAvaliacoes | null> {
  const ator = entrada.actorCollaboratorId;
  if (!ator) return null;

  const [colegiado, responsabilidades, alvoResolvido] = await Promise.all([
    deps.listarColegiado(ator, entrada.organizationId),
    deps.listarResponsabilidades(ator, entrada.organizationId),
    deps.resolverAlvoAvaliativo({
      target: entrada.target,
      cycleId: entrada.cycleId,
      organizationId: entrada.organizationId,
    }),
  ]);

  const alvoPreResolvido =
    alvoResolvido && entrada.target.type === "evaluation"
      ? { evaluationId: entrada.target.id, linha: alvoResolvido }
      : null;

  return {
    collegiateMemberships: colegiado.map((linha) => ({
      cycleId: linha.cycleId,
      organizationId: linha.organizationId,
      evaluatedCollaboratorId: linha.evaluatedCollaboratorId,
      memberCollaboratorId: linha.memberCollaboratorId,
    })),
    evaluationResponsibilities: responsabilidades.map((linha) => ({
      cycleId: linha.cycleId,
      organizationId: linha.organizationId,
      positionId: linha.positionId,
      evaluatedCollaboratorId: linha.evaluatedCollaboratorId,
      responsibleCollaboratorId: linha.responsibleCollaboratorId,
    })),
    resolveEvaluationTarget: criarResolvedorAlvoAvaliativo(alvoPreResolvido),
  };
}

/** Mensagem de diagnóstico interno (nunca devolvida ao cliente). */
export const MOTIVO_ALVO_NAO_RESOLVIDO =
  "Alvo avaliativo sem par (avaliado, posicao) em fonte soberana: ASSIGNED nega (fail-closed).";
