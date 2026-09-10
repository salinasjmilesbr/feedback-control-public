import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import * as feedbackStorage from "./feedbackStorage";
import {
  avaliacaoEstaVaziaParaCleanupInterno,
  escreverNoLegadoEstaProibido,
  existeAvaliacaoNaoCanceladaNoCiclo,
  getFeedbacks,
  getFeedbacksAdministrativosByColaborador,
  getFeedbacksConcluidosByColaborador,
  persistirCancelamentoAuditadoInterno,
  persistirReaberturaAuditadaInterno,
  removerAvaliacaoVaziaNoCleanupInterno,
  updateFeedback,
} from "./feedbackStorage";

/**
 * F5-06 (Issue #103) — LEGADO SOMENTE LEITURA.
 *
 * Depois do cutover, este módulo NÃO é mais autoridade de escrita: a criação,
 * edição, cancelamento e reabertura de avaliações acontecem exclusivamente no
 * PostgreSQL pelo caminho soberano. Os testes abaixo provam:
 *
 * - a LEITURA do acervo legado continua funcionando (compatibilidade histórica);
 * - NENHUMA função de escrita local existe ou grava no `localStorage`;
 * - tentativas de escrita falham de forma explícita (fail-closed), em vez de
 *   gravar localmente por engano.
 */

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

/** Escreve o acervo legado DIRETAMENTE no armazenamento (simula dado antigo). */
function semearLegado(feedbacks: Feedback[]): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(feedbacks));
}

describe("feedbackStorage é somente leitura para o legado", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    semearLegado([avaliacaoConcluida]);
  });

  it("não expõe caminho genérico de exclusão física", () => {
    expect("deleteFeedback" in feedbackStorage).toBe(false);
  });

  it("não expõe nenhuma função de criação de avaliação", () => {
    expect("saveFeedback" in feedbackStorage).toBe(false);
  });

  it("lê o acervo legado preservado", () => {
    expect(getFeedbacks()).toEqual([avaliacaoConcluida]);
  });

  it("oculta canceladas por padrão e inclui somente sob opção administrativa", () => {
    const cancelada = { ...avaliacaoConcluida, status: "CANCELADA" as const };
    semearLegado([avaliacaoConcluida, cancelada]);

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
    semearLegado([cancelada]);

    expect(
      getFeedbacksConcluidosByColaborador(cancelada.colaboradorId)
    ).toEqual([]);
  });

  it("considera cancelada como inexistente para a unicidade de ciclo", () => {
    const cancelada = { ...avaliacaoVazia, status: "CANCELADA" as const };

    expect(
      existeAvaliacaoNaoCanceladaNoCiclo(
        [cancelada],
        cancelada.colaboradorId,
        cancelada.ano,
        cancelada.ciclo
      )
    ).toBe(false);
    expect(
      existeAvaliacaoNaoCanceladaNoCiclo(
        [avaliacaoVazia],
        avaliacaoVazia.colaboradorId,
        avaliacaoVazia.ano,
        avaliacaoVazia.ciclo
      )
    ).toBe(true);
  });
});

describe("feedbackStorage recusa qualquer escrita local (fail-closed)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    semearLegado([avaliacaoVazia]);
  });

  it("updateFeedback recusa a edição e preserva o registro", () => {
    expect(() =>
      updateFeedback({ ...avaliacaoVazia, notaMedia: 5 }, gerente)
    ).toThrow(/escrita de avaliações no armazenamento local foi desativada/i);
    expect(getFeedbacks()).toEqual([avaliacaoVazia]);
  });

  it("cancelamento local recusa e preserva o registro", () => {
    expect(() =>
      persistirCancelamentoAuditadoInterno(
        avaliacaoVazia.id,
        "Motivo",
        gerente,
        "2026-03-01T00:00:00.000Z"
      )
    ).toThrow(/desativada/i);
    expect(getFeedbacks()[0].status).toBe("RASCUNHO");
  });

  it("reabertura local recusa e preserva o registro", () => {
    semearLegado([avaliacaoConcluida]);
    expect(() =>
      persistirReaberturaAuditadaInterno(
        avaliacaoConcluida.id,
        "Motivo",
        gerente,
        "2026-03-01T00:00:00.000Z"
      )
    ).toThrow(/desativada/i);
    expect(getFeedbacks()[0].status).toBe("CONCLUIDA");
  });

  it("cleanup de avaliação vazia recusa a exclusão física do legado", () => {
    expect(() => removerAvaliacaoVaziaNoCleanupInterno(avaliacaoVazia.id)).toThrow(
      /desativada/i
    );
    expect(getFeedbacks()).toHaveLength(1);
  });

  it("cleanup continua exigindo avaliação vazia antes de recusar", () => {
    semearLegado([avaliacaoConcluida]);
    expect(() =>
      removerAvaliacaoVaziaNoCleanupInterno(avaliacaoConcluida.id)
    ).toThrow("O cleanup interno só pode remover avaliações vazias.");
  });

  it("a guarda de escrita é explícita e nomeia a operação", () => {
    expect(() => escreverNoLegadoEstaProibido("teste")).toThrow(
      /teste/
    );
  });
});

describe("avaliacaoEstaVaziaParaCleanupInterno (leitura)", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  it("reconhece avaliação vazia", () => {
    expect(avaliacaoEstaVaziaParaCleanupInterno(avaliacaoVazia)).toBe(true);
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
  ] as const)("não considera vazia quando existe %s", (_tipo, feedback) => {
    expect(avaliacaoEstaVaziaParaCleanupInterno(feedback)).toBe(false);
  });
});
