import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import { getFeedbacks, updateFeedback } from "./feedbackStorage";

const STORAGE_KEY = "feedback-control-feedbacks";

const gerente: Colaborador = {
  matricula: 1,
  status: "ATIVO",
  nome: "Gerente Fictício",
  email: "gerente@example.com",
  cargo: "Gerente",
  area: "Área fictícia",
  funcao: "GERENTE",
  respondePara: "",
};

const avaliacaoConcluida: Feedback = {
  id: "avaliacao-concluida",
  colaboradorId: 2,
  colaboradorNome: "Pessoa Avaliada",
  status: "CONCLUIDA",
  data: "2026-01-10T12:00:00.000Z",
  ano: 2026,
  ciclo: 1,
  competencias: [],
  notaMedia: 4,
};

describe("feedbackStorage", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(STORAGE_KEY, JSON.stringify([avaliacaoConcluida]));
  });

  it("rejeita mutação normal de usuário sobre avaliação concluída", () => {
    expect(() =>
      updateFeedback(
        { ...avaliacaoConcluida, notaMedia: 5 },
        gerente
      )
    ).toThrow("Avaliações concluídas não podem ser alteradas.");

    expect(getFeedbacks()[0].notaMedia).toBe(4);
  });

  it("preserva a mutação interna sem ator usada no encerramento de ciclo", () => {
    updateFeedback({
      ...avaliacaoConcluida,
      encerradaComPendencias: true,
    });

    expect(getFeedbacks()[0].encerradaComPendencias).toBe(true);
  });
});
