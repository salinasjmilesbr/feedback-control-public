import { obterPermissoesAvaliacao } from "../services/permissaoAvaliacao";
import { podeAprovarMetaNoCiclo } from "../services/metaStorage";
import { aplicarEscopoRelatorio } from "../services/relatorioService";
import { getColaboradoresVisiveis } from "../services/visibilidadeColaboradores";
import type { Colaborador } from "../types/Colaborador";
import type { AuthorizationContext } from "./AuthorizationContext";
import type { Capability } from "./Capability";
import type {
  AuthorizationResource,
  CollaboratorScopeInput,
} from "./ResourceContext";
import { AuthorizationError } from "./authorizationError";

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

function decidir(
  context: AuthorizationContext,
  capability: Capability,
  resource: AuthorizationResource
): boolean {
  const { actor } = context;

  if (capability === "collaborator.create") {
    return resource.kind === "global" && actor.funcao === "GERENTE";
  }

  if (capability === "collaborator.edit") {
    return resource.kind === "collaborator" && actor.funcao === "GERENTE";
  }

  if (capability === "collaborator.list") {
    if (resource.kind !== "collaborator-list") return false;
    const actor = resolverAtor(context, resource.collaborators);
    return (
      actor !== undefined &&
      (actor.funcao === "GERENTE" || actor.funcao === "COORDENADOR")
    );
  }

  if (capability === "report.view") {
    return (
      resource.kind === "global" &&
      (actor.funcao === "GERENTE" || actor.funcao === "COORDENADOR")
    );
  }

  if (capability === "cycle.management.view") {
    return resource.kind === "global" && actor.funcao === "GERENTE";
  }

  if (capability === "cycle.cancel.manager") {
    return (
      resource.kind === "cycle" &&
      resource.cycle.status === "ATIVO" &&
      actor.funcao === "GERENTE"
    );
  }

  if (capability === "cycle.reopen.manager") {
    return (
      resource.kind === "cycle" &&
      resource.cycle.status === "ENCERRADO" &&
      actor.funcao === "GERENTE"
    );
  }

  if (capability === "cycle.coordinator.list") {
    return resource.kind === "global" && actor.funcao === "COORDENADOR";
  }

  if (capability === "settings.manage") {
    return resource.kind === "global" && actor.funcao === "GERENTE";
  }

  if (capability === "cycle.team.panel.view") {
    return (
      resource.kind === "global" &&
      (actor.funcao === "GERENTE" || actor.funcao === "COORDENADOR")
    );
  }

  if (capability === "observation.create") {
    return (
      resource.kind === "observation" &&
      resource.cycle?.status !== "CANCELADO" &&
      resource.collaborator.status !== "DESLIGADO" &&
      (actor.funcao === "GERENTE" || actor.funcao === "COORDENADOR")
    );
  }

  if (
    capability === "observation.edit" ||
    capability === "observation.delete"
  ) {
    return (
      resource.kind === "observation" &&
      resource.cycle?.status !== "CANCELADO" &&
      (actor.funcao === "GERENTE" || actor.funcao === "COORDENADOR")
    );
  }

  if (resource.kind === "evaluation") {
    const actor = resolverAtor(context, resource.collaborators);
    if (!actor) return false;
    const permissoes = obterPermissoesAvaliacao(
      actor,
      resource.evaluatedCollaborator,
      [...resource.collaborators],
      resource.cycle
    );

    if (capability === "evaluation.create") {
      return (
        resource.cycle?.status !== "CANCELADO" &&
        resource.evaluatedCollaborator.status === "ATIVO" &&
        (permissoes.podeAvaliarComoGerente ||
          permissoes.podeAvaliarComoCoordenador ||
          permissoes.podeAvaliarComoColegiado)
      );
    }

    if (capability === "evaluation.view.admin") {
      return permissoes.podeAvaliar;
    }

    if (capability === "evaluation.cancel.manager") {
      return (
        resource.cycle?.status !== "CANCELADO" &&
        resource.evaluationStatus !== "CANCELADA" &&
        permissoes.podeAvaliarComoGerente
      );
    }

    if (capability === "evaluation.reopen.manager") {
      return (
        resource.evaluationStatus === "CONCLUIDA" &&
        resource.cycle?.status !== "ENCERRADO" &&
        resource.cycle?.status !== "CANCELADO" &&
        permissoes.podeAvaliarComoGerente
      );
    }

    if (
      (resource.cycle?.status === "CANCELADO" ||
        resource.evaluationStatus === "CONCLUIDA" ||
        resource.evaluationStatus === "CANCELADA") &&
      (capability === "evaluation.edit.manager" ||
        capability === "evaluation.edit.coordinator" ||
        capability === "evaluation.edit.board")
    ) {
      return false;
    }

    if (capability === "evaluation.edit.manager") {
      return permissoes.podeAvaliarComoGerente;
    }
    if (capability === "evaluation.edit.coordinator") {
      return permissoes.podeAvaliarComoCoordenador;
    }
    if (capability === "evaluation.edit.board") {
      return permissoes.podeAvaliarComoColegiado;
    }
  }

  if (resource.kind === "goal") {
    const actor = resolverAtor(context, resource.collaborators);
    if (!actor) return false;
    const podeAprovar = podeAprovarMetaNoCiclo(
      actor,
      resource.owner,
      [...resource.collaborators],
      resource.cycle
    );

    if (capability === "goal.view.admin") {
      return podeAprovar;
    }

    if (capability === "goal.approve.manager") {
      return (
        resource.cycle.status !== "CANCELADO" &&
        actor.funcao === "GERENTE" &&
        podeAprovar
      );
    }
    if (capability === "goal.approve.coordinator") {
      return (
        resource.cycle.status !== "CANCELADO" &&
        actor.funcao === "COORDENADOR" &&
        podeAprovar
      );
    }
  }

  return false;
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

  const visiveis = getColaboradoresVisiveis(
    actor,
    [...input.collaborators]
  );

  if (input.purpose === "REPORT") {
    return aplicarEscopoRelatorio(
      visiveis.map((colaborador) => ({ colaborador })),
      actor
    ).map(({ colaborador }) => colaborador);
  }

  return visiveis;
}
