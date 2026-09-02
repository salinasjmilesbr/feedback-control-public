import { authorize } from "../authorization/authorizationPolicy";
import type { AuthorizationContext } from "../authorization/AuthorizationContext";
import type { EvaluationResource } from "../authorization/ResourceContext";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import { getCiclosAvaliacao } from "./cicloAvaliacaoStorage";
import { getColaboradores } from "./colaboradorStorage";
import {
  getFeedbacks,
  persistirReaberturaAuditadaInterno,
} from "./feedbackStorage";

export function reabrirAvaliacao(
  feedbackId: string,
  motivoInformado: string,
  autor: Colaborador
): Feedback {
  const motivo = motivoInformado.trim();
  if (!motivo) throw new Error("Informe o motivo da reabertura.");

  const feedback = getFeedbacks().find((item) => item.id === feedbackId);
  if (!feedback) throw new Error("Avaliação não encontrada.");

  const colaboradores = getColaboradores();
  const colaborador = colaboradores.find(
    (item) => item.matricula === feedback.colaboradorId
  );
  if (!colaborador) throw new Error("Colaborador não encontrado.");

  const ciclo = getCiclosAvaliacao().find(
    (item) => item.ano === feedback.ano && item.ciclo === feedback.ciclo
  );
  const context: AuthorizationContext = {
    actor: {
      matricula: autor.matricula,
      funcao: autor.funcao,
      status: autor.status,
    },
  };
  const resource: EvaluationResource = {
    kind: "evaluation",
    evaluatedCollaborator: colaborador,
    collaborators: colaboradores,
    cycle: ciclo,
    evaluationStatus: feedback.status,
  };
  authorize(context, "evaluation.reopen.manager", resource);

  return persistirReaberturaAuditadaInterno(
    feedback.id,
    motivo,
    autor,
    new Date().toISOString()
  );
}
