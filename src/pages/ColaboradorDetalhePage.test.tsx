import { describe, expect, it } from "vitest";
import type { Feedback } from "../types/Feedback";
import { labelStatusFeedback } from "./statusAvaliacaoAdministrativa";

describe("status administrativo da avaliação", () => {
  it("prioriza o contexto de ciclo cancelado sem alterar o status persistido", () => {
    const feedback = { status: "RASCUNHO" } as Feedback;
    expect(labelStatusFeedback(feedback.status, true)).toBe("Ciclo cancelado");
    expect(feedback.status).toBe("RASCUNHO");
  });
});
