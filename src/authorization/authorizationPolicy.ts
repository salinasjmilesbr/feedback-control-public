import { getColaboradores } from "../services/colaboradorStorage";
import { aplicarEscopoRelatorio } from "../services/relatorioService";
import { getColaboradoresVisiveis } from "../services/visibilidadeColaboradores";
import type { Colaborador } from "../types/Colaborador";
import type { AuthorizationContext } from "./AuthorizationContext";
import { alvosPermitidos } from "./autorizacaoFuncional";
import { canonicalizarCapability } from "./canonical";
import type { Capability } from "./Capability";
import {
  criarProvidersMundoFuncional,
  estaNaCadeiaDeGestao,
  LOCAL_ORGANIZATION_ID,
} from "./mundoFuncional";
import type { DomainStateProbe, TargetRef } from "./policyEngine/types";
import { can as canEngine } from "./policyEngine/policyEngine";
import type {
  AuthorizationResource,
  CollaboratorScopeInput,
} from "./ResourceContext";
import { AuthorizationError } from "./authorizationError";

/**
 * F4-09 (Issue #96): adaptador de COMPATIBILIDADE — a decisão real é do Policy
 * Engine (`policyEngine.decidir`), alimentado por providers derivados dos DADOS
 * (`mundoFuncional`, nunca `funcao`/`cargo`). Aqui NÃO existe regra soberana de
 * autorização nem derivação de papel por `funcao`: este módulo apenas traduz o
 * vocabulário legado (capability + resource) para uma requisição do engine
 * (capability canônica + target + domainState) e delega.
 */

function dominioPermite(permite: boolean): DomainStateProbe {
  return { allows: () => permite };
}

function resolverAtor(
  context: AuthorizationContext,
  colaboradores: readonly Colaborador[]
): Colaborador | undefined {
  const colaborador = colaboradores.find(
    (colaborador) => colaborador.matricula === context.actor.matricula
  );
  if (!colaborador) return undefined;

  return {
    ...colaborador,
    matricula: context.actor.matricula,
    funcao: context.actor.funcao,
    status: context.actor.status,
  };
}

/** Mundo funcional: recurso carregado quando presente; senão, tenant do storage. */
function colaboradoresDoRecurso(
  resource: AuthorizationResource
): readonly Colaborador[] {
  const colaboradores = (
    resource as { collaborators?: readonly Colaborador[] }
  ).collaborators;
  if (colaboradores && colaboradores.length > 0) return colaboradores;
  try {
    return getColaboradores();
  } catch {
    // Storage indisponível ⇒ mundo vazio ⇒ ator não resolvido ⇒ DENY (fail-closed).
    return [];
  }
}

interface RequisicaoEngine {
  capability: Capability;
  target: TargetRef;
  domainState: DomainStateProbe;
  cycleId?: string;
}

/**
 * Traduz capability legada + resource em uma requisição do engine. Retorna null
 * quando a combinação é incompatível (fail-closed ⇒ DENY).
 */
function requisicaoEngine(
  ator: Colaborador,
  colaboradores: readonly Colaborador[],
  capability: Capability,
  resource: AuthorizationResource
): RequisicaoEngine | null {
  const canonica = canonicalizarCapability(capability);
  const atorId = ator.matricula;

  switch (resource.kind) {
    case "evaluation": {
      const alvo: TargetRef = {
        type: "collaborator",
        id: String(resource.evaluatedCollaborator.matricula),
      };
      const status = resource.evaluationStatus;
      const cicloStatus = resource.cycle?.status;
      const cycleId = resource.cycle?.id;

      switch (canonica) {
        case "evaluation.create":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              cicloStatus !== "CANCELADO" &&
                resource.evaluatedCollaborator.status === "ATIVO"
            ),
          };
        case "evaluation.read":
          // view.admin é leitura ADMINISTRATIVA de terceiro; SELF não usa o alias.
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              atorId !== resource.evaluatedCollaborator.matricula
            ),
          };
        case "evaluation.write":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              cicloStatus !== "CANCELADO" &&
                status !== "CONCLUIDA" &&
                status !== "CANCELADA"
            ),
          };
        case "evaluation.cancel":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              cicloStatus !== "CANCELADO" && status !== "CANCELADA"
            ),
          };
        case "evaluation.reopen":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              status === "CONCLUIDA" &&
                cicloStatus !== "ENCERRADO" &&
                cicloStatus !== "CANCELADO"
            ),
          };
        default:
          return null;
      }
    }

    case "goal": {
      const alvo: TargetRef = {
        type: "collaborator",
        id: String(resource.owner.matricula),
      };
      const cycleId = resource.cycle.id;

      switch (canonica) {
        case "goal.read":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(true),
          };
        case "goal.approve":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              resource.cycle.status === "ATIVO" &&
                estaNaCadeiaDeGestao(ator, resource.owner, colaboradores)
            ),
          };
        case "goal.write":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              resource.cycle.status === "ATIVO" &&
                ator.matricula === resource.owner.matricula
            ),
          };
        default:
          return null;
      }
    }

    case "observation": {
      const alvo: TargetRef = {
        type: "collaborator",
        id: String(resource.collaborator.matricula),
      };
      const cicloAtivo = resource.cycle?.status === "ATIVO";
      const cycleId = resource.cycle?.id;

      switch (canonica) {
        case "observation.create":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(
              cicloAtivo && resource.collaborator.status !== "DESLIGADO"
            ),
          };
        case "observation.edit":
        case "observation.delete":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(cicloAtivo),
          };
        case "observation.read":
          return {
            capability: canonica,
            target: alvo,
            cycleId,
            domainState: dominioPermite(true),
          };
        default:
          return null;
      }
    }

    case "cycle": {
      const alvo: TargetRef = { type: "cycle", id: resource.cycle.id };

      switch (canonica) {
        case "cycle.cancel":
        case "cycle.period.correct":
          return {
            capability: canonica,
            target: alvo,
            cycleId: resource.cycle.id,
            domainState: dominioPermite(resource.cycle.status === "ATIVO"),
          };
        case "cycle.reopen":
          return {
            capability: canonica,
            target: alvo,
            cycleId: resource.cycle.id,
            domainState: dominioPermite(resource.cycle.status === "ENCERRADO"),
          };
        default:
          return null;
      }
    }

    case "collaborator": {
      const alvo: TargetRef = {
        type: "collaborator",
        id: String(resource.collaborator.matricula),
      };

      switch (canonica) {
        case "collaborator.edit":
        case "collaborator.read":
          return {
            capability: canonica,
            target: alvo,
            domainState: dominioPermite(true),
          };
        default:
          return null;
      }
    }

    case "collaborator-list": {
      // Gate de "posso listar": capability sobre o próprio ator (SELF).
      const alvo: TargetRef = { type: "collaborator", id: String(atorId) };

      switch (canonica) {
        case "collaborator.read":
          return {
            capability: canonica,
            target: alvo,
            domainState: dominioPermite(true),
          };
        default:
          return null;
      }
    }

    case "global": {
      const alvoSelf: TargetRef = { type: "collaborator", id: String(atorId) };
      const alvoCiclo: TargetRef = { type: "cycle", id: "global" };

      switch (canonica) {
        case "collaborator.create":
          return {
            capability: canonica,
            target: alvoSelf,
            domainState: dominioPermite(true),
          };
        case "report.read":
        case "cycle.read":
          // Gates de navegação: report.view / cycle.management.view /
          // cycle.coordinator.list / cycle.team.panel.view.
          return {
            capability: canonica,
            target: alvoSelf,
            domainState: dominioPermite(true),
          };
        case "settings.manage":
          return {
            capability: canonica,
            target: alvoCiclo,
            domainState: dominioPermite(true),
          };
        default:
          return null;
      }
    }
  }
}

function decidir(
  context: AuthorizationContext,
  capability: Capability,
  resource: AuthorizationResource
): boolean {
  const colaboradores = colaboradoresDoRecurso(resource);
  const ator = resolverAtor(context, colaboradores);
  if (!ator) return false;

  const requisicao = requisicaoEngine(ator, colaboradores, capability, resource);
  if (!requisicao) return false;

  const decisao = canEngine(
    {
      actor: {
        actorId: String(ator.matricula),
        organizationId: LOCAL_ORGANIZATION_ID,
      },
      capability: requisicao.capability,
      target: requisicao.target,
      context: { date: new Date(), cycleId: requisicao.cycleId },
      domainState: requisicao.domainState,
    },
    criarProvidersMundoFuncional({ actor: ator, colaboradores })
  );

  return decisao.allowed;
}

export function can(
  context: AuthorizationContext,
  capability: Capability,
  resource: AuthorizationResource
): boolean {
  return decidir(context, capability, resource);
}

export function authorize(
  context: AuthorizationContext,
  capability: Capability,
  resource: AuthorizationResource
): void {
  if (!decidir(context, capability, resource)) {
    throw new AuthorizationError(capability);
  }
}

export function scopeCollaborators(
  context: AuthorizationContext,
  input: CollaboratorScopeInput
): readonly Colaborador[] {
  const actor = resolverAtor(context, input.collaborators);
  if (!actor) return [];

  // 1) Descoberta de CANDIDATOS (dados/hierarquia + UX). NÃO é autorização.
  const visiveis = getColaboradoresVisiveis(
    actor,
    [...input.collaborators]
  );
  const candidatos =
    input.purpose === "REPORT"
      ? aplicarEscopoRelatorio(
          visiveis.map((colaborador) => ({ colaborador })),
          actor
        ).map(({ colaborador }) => colaborador)
      : visiveis;

  // 2) Decisão FINAL via Policy Engine (capability + target + scope + relação +
  //    domainState). Somente ALLOW permanece (fail-closed).
  const capability: Capability =
    input.purpose === "REPORT" ? "report.read" : "collaborator.read";
  const permitidos = alvosPermitidos(
    actor,
    [...input.collaborators],
    capability,
    input.domainState ?? dominioPermite(true),
    input.cicloId,
    input.bindingsDev
  );
  const idsPermitidos = new Set(permitidos.map((c) => c.matricula));

  return candidatos.filter((c) => idsPermitidos.has(c.matricula));
}
