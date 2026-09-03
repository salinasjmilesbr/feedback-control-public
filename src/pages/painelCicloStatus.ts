import type { StatusCicloAvaliacao } from "../types/CicloAvaliacao";
import type { SituacaoAvaliacaoCiclo } from "../services/cicloEquipeService";

const labels: Record<SituacaoAvaliacaoCiclo, string> = {
  NAO_INICIADA: "Não iniciada",
  EM_ANDAMENTO: "Em andamento",
  PRONTA_PARA_FEEDBACK: "Pronta para Feedback",
  CONCLUIDA: "Concluída",
  CANCELADA: "Cancelada",
  SUSPENSA: "Suspensa",
  NAO_APLICAVEL: "Não aplicável",
};

export function getStatusGeralPainel(
  situacao: SituacaoAvaliacaoCiclo,
  statusCiclo: StatusCicloAvaliacao
) {
  if (statusCiclo === "CANCELADO" || situacao === "CANCELADA") {
    return { label: "Cancelado", className: "is-historical" };
  }
  if (situacao === "CONCLUIDA") {
    return { label: labels[situacao], className: "is-complete" };
  }
  if (situacao === "PRONTA_PARA_FEEDBACK") {
    return { label: labels[situacao], className: "is-feedback" };
  }
  if (situacao === "EM_ANDAMENTO") {
    return { label: labels[situacao], className: "is-progress" };
  }
  if (situacao === "SUSPENSA" || situacao === "NAO_APLICAVEL") {
    return { label: labels[situacao], className: "is-na" };
  }
  return { label: labels[situacao], className: "is-not-started" };
}
