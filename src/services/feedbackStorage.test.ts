import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import * as feedbackStorage from "./feedbackStorage";
import {
  getFeedbacks,
  getFeedbacksAdministrativosByColaborador,
  getFeedbacksConcluidosByColaborador,
  removerAvaliacaoVaziaNoCleanupInterno,
  updateFeedback,
} from "./feedbackStorage";

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

const avaliacaoVazia: Feedback = {
  ...avaliacaoConcluida,
  id: "avaliacao-vazia",
  status: "RASCUNHO",
  notaMedia: 0,
  competencias: [
    {
      competenciaId: "competencia",
      competenciaNome: "Competência fictícia",
      nota: 0,
      comentario: "",
    },
  ],
  criteriosDetalhados: [
    {
      criterioId: "criterio",
      criterioNome: "Critério fictício",
      nota: 0,
      observacaoGerente: "",
      observacaoCoordenador: "",
      subcriterios: [
        {
          nome: "Subcritério fictício",
          notaGerente: 0,
          notaCoordenador: 0,
          notaColegiado: 0,
          votosColegiado: [],
          notaFinal: 0,
        },
      ],
    },
  ],
  feedbackFinalGerente: "",
  feedbackFinalCoordenador: "",
};

describe("feedbackStorage", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(STORAGE_KEY, JSON.stringify([avaliacaoConcluida]));
  });

  it("não expõe caminho genérico de exclusão física", () => {
    expect("deleteFeedback" in feedbackStorage).toBe(false);
  });

  it("oculta canceladas por padrão e inclui somente sob opção administrativa", () => {
    const cancelada = { ...avaliacaoConcluida, status: "CANCELADA" as const };
    localStorage.setItem(STORAGE_KEY, JSON.stringify([avaliacaoConcluida, cancelada]));

    expect(
      getFeedbacksAdministrativosByColaborador(avaliacaoConcluida.colaboradorId)
    ).toEqual([avaliacaoConcluida]);
    expect(
      getFeedbacksAdministrativosByColaborador(
        avaliacaoConcluida.colaboradorId,
        true
      )
    ).toHaveLength(2);
  });

  it("mantém canceladas fora das avaliações concluídas do avaliado", () => {
    const cancelada = { ...avaliacaoConcluida, status: "CANCELADA" as const };
    localStorage.setItem(STORAGE_KEY, JSON.stringify([cancelada]));

    expect(
      getFeedbacksConcluidosByColaborador(cancelada.colaboradorId)
    ).toEqual([]);
  });

  it("remove avaliação realmente vazia somente pelo cleanup interno", () => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify([avaliacaoVazia]));

    removerAvaliacaoVaziaNoCleanupInterno(avaliacaoVazia.id);

    expect(getFeedbacks()).toEqual([]);
  });

  it.each([
    [
      "nota",
      {
        ...avaliacaoVazia,
        criteriosDetalhados: avaliacaoVazia.criteriosDetalhados?.map(
          (criterio) => ({
            ...criterio,
            subcriterios: criterio.subcriterios.map((subcriterio) => ({
              ...subcriterio,
              notaGerente: 4,
            })),
          })
        ),
      },
    ],
    [
      "comentário",
      {
        ...avaliacaoVazia,
        competencias: avaliacaoVazia.competencias.map((competencia) => ({
          ...competencia,
          comentario: "Comentário operacional",
        })),
      },
    ],
    [
      "observação",
      {
        ...avaliacaoVazia,
        criteriosDetalhados: avaliacaoVazia.criteriosDetalhados?.map(
          (criterio) => ({
            ...criterio,
            observacaoCoordenador: "Observação operacional",
          })
        ),
      },
    ],
    [
      "voto",
      {
        ...avaliacaoVazia,
        criteriosDetalhados: avaliacaoVazia.criteriosDetalhados?.map(
          (criterio) => ({
            ...criterio,
            subcriterios: criterio.subcriterios.map((subcriterio) => ({
              ...subcriterio,
              votosColegiado: [
                {
                  avaliadorMatricula: 3,
                  avaliadorNome: "Pessoa Avaliadora",
                  nota: 4,
                },
              ],
            })),
          })
        ),
      },
    ],
    [
      "feedback final",
      { ...avaliacaoVazia, feedbackFinalGerente: "Feedback operacional" },
    ],
  ] as const)("rejeita cleanup interno quando existe %s", (_tipo, feedback) => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify([feedback]));

    expect(() =>
      removerAvaliacaoVaziaNoCleanupInterno(feedback.id)
    ).toThrow("O cleanup interno só pode remover avaliações vazias.");
    expect(getFeedbacks()).toHaveLength(1);
  });

  it("rejeita mutação normal de usuário sobre avaliação concluída", () => {
    expect(() =>
      updateFeedback(
        { ...avaliacaoConcluida, notaMedia: 5 },
        gerente
      )
    ).toThrow("Avaliações concluídas ou canceladas não podem ser alteradas.");

    expect(getFeedbacks()[0].notaMedia).toBe(4);
  });

  it("rejeita mutação normal de usuário sobre avaliação cancelada", () => {
    const cancelada = { ...avaliacaoConcluida, status: "CANCELADA" as const };
    localStorage.setItem(STORAGE_KEY, JSON.stringify([cancelada]));

    expect(() =>
      updateFeedback({ ...cancelada, notaMedia: 5 }, gerente)
    ).toThrow("Avaliações concluídas ou canceladas não podem ser alteradas.");
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
