import { describe, expect, it } from "vitest";
import type { Feedback } from "../types/Feedback";
import { getStatusAvaliacaoAdministrativa } from "./statusAvaliacaoAdministrativa";

describe("status administrativo da avaliação", () => {
  it("prioriza o contexto de ciclo cancelado sem alterar o status persistido", () => {
    const feedback = { status: "RASCUNHO" } as Feedback;
    expect(getStatusAvaliacaoAdministrativa(feedback.status, "CANCELADO")).toEqual({
      label: "Cancelado",
      className: "is-historical",
    });
    expect(feedback.status).toBe("RASCUNHO");
  });

  it("apresenta rascunho de ciclo encerrado com o mesmo tratamento neutro", () => {
    const feedback = { status: "RASCUNHO" } as Feedback;
    expect(getStatusAvaliacaoAdministrativa(feedback.status, "ENCERRADO")).toEqual({
      label: "Encerrado",
      className: "is-historical",
    });
    expect(feedback.status).toBe("RASCUNHO");
  });
});
