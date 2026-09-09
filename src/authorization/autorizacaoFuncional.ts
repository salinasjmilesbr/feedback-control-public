import type { Colaborador } from "../types/Colaborador";
import type { Capability } from "./Capability";
import { canonicalizarCapability } from "./canonical";
import {
  criarProvidersMundoFuncional,
  LOCAL_ORGANIZATION_ID,
  type DevCapabilityBindings,
} from "./mundoFuncional";
import {
  authorize as authorizeEngine,
  can as canEngine,
  listAllowedTargets as listAllowedTargetsEngine,
} from "./policyEngine/policyEngine";
import type {
  AuthorizationDecision,
  DomainStateProbe,
  TargetRef,
} from "./policyEngine/types";

/**
 * Facade de autorização funcional F4-09 (D1/D2/D3): a fronteira de enforcement
 * na camada de aplicação. `authorize` = enforcement; `pode` = UX; os alvos são
 * SEMPRE derivados do recurso carregado pelo serviço (nunca de ids do cliente).
 *
 * capability é canonicalizada (Q1); o mundo é derivado dos dados (nunca cargo).
 */

export function providersPara(
  ator: Colaborador,
  colaboradores: readonly Colaborador[],
  bindingsDev?: DevCapabilityBindings
) {
  return criarProvidersMundoFuncional({ actor: ator, colaboradores, bindingsDev });
}

export interface OperacaoFuncional {
  capability: Capability;
  /** Sujeito do recurso (colaborador alvo) derivado do recurso carregado. */
  sujeitoMatricula: number;
  domainState: DomainStateProbe;
  cicloId?: string;
  data?: Date;
}

export function autorizar(
  ator: Colaborador,
  colaboradores: readonly Colaborador[],
  operacao: OperacaoFuncional,
  bindingsDev?: DevCapabilityBindings
): void {
  authorizeEngine(
    {
      actor: {
        actorId: String(ator.matricula),
        organizationId: LOCAL_ORGANIZATION_ID,
      },
      capability: canonicalizarCapability(operacao.capability),
      target: {
        type: "collaborator",
        id: String(operacao.sujeitoMatricula),
      },
      context: {
        date: operacao.data ?? new Date(),
        cycleId: operacao.cicloId,
      },
      domainState: operacao.domainState,
    },
    providersPara(ator, colaboradores, bindingsDev)
  );
}

export function pode(
  ator: Colaborador,
  colaboradores: readonly Colaborador[],
  operacao: OperacaoFuncional,
  bindingsDev?: DevCapabilityBindings
): AuthorizationDecision {
  return canEngine(
    {
      actor: {
        actorId: String(ator.matricula),
        organizationId: LOCAL_ORGANIZATION_ID,
      },
      capability: canonicalizarCapability(operacao.capability),
      target: {
        type: "collaborator",
        id: String(operacao.sujeitoMatricula),
      },
      context: {
        date: operacao.data ?? new Date(),
        cycleId: operacao.cicloId,
      },
      domainState: operacao.domainState,
    },
    providersPara(ator, colaboradores, bindingsDev)
  );
}

export function alvosPermitidos(
  ator: Colaborador,
  colaboradores: readonly Colaborador[],
  capability: Capability,
  domainState: DomainStateProbe,
  cicloId?: string,
  bindingsDev?: DevCapabilityBindings
): readonly Colaborador[] {
  const candidatos: TargetRef[] = colaboradores.map((c) => ({
    type: "collaborator" as const,
    id: String(c.matricula),
  }));
  const permitidos = listAllowedTargetsEngine(
    {
      actor: {
        actorId: String(ator.matricula),
        organizationId: LOCAL_ORGANIZATION_ID,
      },
      capability: canonicalizarCapability(capability),
      context: { date: new Date(), cycleId: cicloId },
      domainState,
    },
    providersPara(ator, colaboradores, bindingsDev),
    candidatos
  );
  const ids = new Set(permitidos.map((t) => Number(t.id)));
  return colaboradores.filter((c) => ids.has(c.matricula));
}

export function dominioPermite(permite: boolean): DomainStateProbe {
  return { allows: () => permite };
}
