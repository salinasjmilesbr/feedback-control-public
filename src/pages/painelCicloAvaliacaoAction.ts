import { can } from "../authorization/authorizationPolicy";
import type { Capability } from "../authorization/Capability";
import type { EvaluationResource } from "../authorization/ResourceContext";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";

export function obterAcaoAvaliacaoPainel(
  usuario: Colaborador,
  colaborador: Colaborador,
  colaboradores: Colaborador[],
  ciclo: CicloAvaliacao,
  feedback: Feedback
) {
  const resource: EvaluationResource = {
    kind: "evaluation",
    evaluatedCollaborator: colaborador,
    collaborators: colaboradores,
    cycle: ciclo,
    evaluationStatus: feedback.status,
  };
  const context = { actor: usuario };
  const capabilitiesEdicao: Capability[] = [
    "evaluation.edit.manager",
    "evaluation.edit.coordinator",
    "evaluation.edit.board",
  ];
  const base = `/colaborador/${colaborador.matricula}/feedback/${feedback.id}`;

  if (capabilitiesEdicao.some((capability) => can(context, capability, resource))) {
    return { label: "Abrir avaliação", destino: `${base}/editar` };
  }
  if (can(context, "evaluation.view.admin", resource)) {
    return { label: "Ver avaliação", destino: base };
  }
  return undefined;
}
