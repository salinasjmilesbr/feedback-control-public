import { can } from "../authorization/authorizationPolicy";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";

export function ordenarHistoricoAdministrativo(
  feedbacks: Feedback[],
  ordem: "RECENTES" | "ANTIGAS"
): Feedback[] {
  const direcao = ordem === "RECENTES" ? -1 : 1;
  return [...feedbacks].sort((a, b) => {
    const porAno = (a.ano - b.ano) * direcao;
    if (porAno !== 0) return porAno;
    const porCiclo = (a.ciclo - b.ciclo) * direcao;
    if (porCiclo !== 0) return porCiclo;
    return a.id.localeCompare(b.id);
  });
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
