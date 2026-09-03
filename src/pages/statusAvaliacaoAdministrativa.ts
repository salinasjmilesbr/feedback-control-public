import type { Feedback } from "../types/Feedback";

export function labelStatusFeedback(
  status: Feedback["status"],
  cicloCancelado = false
) {
  if (cicloCancelado) return "Ciclo cancelado";
  if (status === "CANCELADA") return "Cancelada";
  if (status === "CONCLUIDA") return "Concluída";
  if (status === "PRONTA_PARA_FEEDBACK") return "Pronta para feedback";
  return "Em andamento";
}
