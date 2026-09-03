import { can } from "../authorization/authorizationPolicy";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import { ordenarPorAnoECiclo } from "../utils/ordenacaoPorCiclo";

export function ordenarHistoricoAdministrativo(
  feedbacks: Feedback[],
  ordem: "RECENTES" | "ANTIGAS"
): Feedback[] {
  return ordenarPorAnoECiclo(feedbacks, ordem);
}

export function getAcaoConsultaHistoricoAdministrativo(
  usuario: Colaborador,
  colaborador: Colaborador,
  colaboradores: Colaborador[],
  ciclo: CicloAvaliacao | undefined,
  feedback: Feedback
) {
  const podeConsultar = can(
    { actor: usuario },
    "evaluation.view.admin",
    {
      kind: "evaluation",
      evaluatedCollaborator: colaborador,
      collaborators: colaboradores,
      cycle: ciclo,
      evaluationStatus: feedback.status,
    }
  );

  return podeConsultar
    ? {
        label: "Ver avaliação",
        destino: `/colaborador/${colaborador.matricula}/feedback/${feedback.id}`,
      }
    : undefined;
}
