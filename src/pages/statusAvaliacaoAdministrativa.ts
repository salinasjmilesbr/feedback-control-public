import type { Feedback } from "../types/Feedback";
import type { StatusCicloAvaliacao } from "../types/CicloAvaliacao";

export function getStatusAvaliacaoAdministrativa(
  status: Feedback["status"],
  statusCiclo?: StatusCicloAvaliacao
) {
  if (status === "CANCELADA" || statusCiclo === "CANCELADO") {
    return { label: "Cancelado", className: "is-historical" };
  }
  if (status === "CONCLUIDA") {
    return { label: "Concluída", className: "is-complete" };
  }
  if (statusCiclo === "ENCERRADO") {
    return { label: "Encerrado", className: "is-historical" };
  }
  if (status === "PRONTA_PARA_FEEDBACK") {
    return { label: "Pronta para feedback", className: "is-ready" };
  }
  return { label: "Em andamento", className: "is-progress" };
}
