import { beforeEach, describe, expect, it } from "vitest";
import { AuthorizationError } from "../authorization/authorizationError";
import { can } from "../authorization/authorizationPolicy";
import type { AuthorizationContext } from "../authorization/AuthorizationContext";
import type { EvaluationResource } from "../authorization/ResourceContext";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import { getFeedbacks, updateFeedback } from "./feedbackStorage";
import { reabrirAvaliacao } from "./reaberturaAvaliacaoService";

function pessoa(
  matricula: number,
  funcao: Colaborador["funcao"],
  gestorDiretoMatricula?: number,
  colegiado?: number[]
): Colaborador {
  return {
    matricula,
    status: "ATIVO",
    nome: `Pessoa ${matricula}`,
    email: `${matricula}@example.com`,
    cargo: funcao ?? "Sem função",
    area: "Área fictícia",
    funcao,
    gestorDiretoMatricula,
    avaliadoresColegiadoMatriculas: colegiado,
    respondePara: "",
  };
}

const gerente = pessoa(1, "GERENTE");
const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
const colegiado = pessoa(3, "COORDENADOR", gerente.matricula);
const avaliado = pessoa(4, "ANALISTA", coordenador.matricula, [colegiado.matricula]);
const colaboradores = [gerente, coordenador, colegiado, avaliado];
const ciclo: CicloAvaliacao = {
  id: "ciclo-reabertura",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};
const feedback: Feedback = {
  id: "avaliacao-concluida",
  colaboradorId: avaliado.matricula,
  colaboradorNome: avaliado.nome,
  status: "CONCLUIDA",
  data: "2026-01-10T00:00:00.000Z",
  dataConclusao: "2026-02-01T00:00:00.000Z",
  ano: 2026,
  ciclo: 1,
  notaMedia: 4,
  competencias: [
    {
      competenciaId: "qualidade",
      competenciaNome: "Qualidade",
      nota: 4,
      comentario: "Comentário preservado",
    },
  ],
  criteriosDetalhados: [
    {
      criterioId: "entrega",
      criterioNome: "Entrega",
      nota: 4,
      observacaoGerente: "Observação preservada",
      observacaoCoordenador: "Outra observação",
      subcriterios: [
        {
          nome: "Qualidade",
          notaGerente: 4,
          notaCoordenador: 4,
          notaColegiado: 5,
          votosColegiado: [
            {
              avaliadorMatricula: colegiado.matricula,
              avaliadorNome: colegiado.nome,
              nota: 5,
            },
          ],
          notaFinal: 4.3,
        },
      ],
    },
  ],
  feedbackFinalGerente: "Feedback final preservado",
  feedbackFinalCoordenador: "Feedback da coordenação preservado",
};

function contexto(actor: Colaborador): AuthorizationContext {
  return {
    actor: {
      matricula: actor.matricula,
      funcao: actor.funcao,
      status: actor.status,
    },
  };
}

describe("reabrirAvaliacao", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem("feedback-control-colaboradores", JSON.stringify(colaboradores));
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([ciclo]));
    localStorage.setItem("feedback-control-feedbacks", JSON.stringify([feedback]));
  });

  it("permite ao gerente responsável reabrir com auditoria e preserva o conteúdo", () => {
    const reaberta = reabrirAvaliacao(feedback.id, "  Corrigir lançamento  ", gerente);

    expect(reaberta).toMatchObject({
      ...feedback,
      status: "RASCUNHO",
      competencias: feedback.competencias,
      criteriosDetalhados: feedback.criteriosDetalhados,
      feedbackFinalGerente: feedback.feedbackFinalGerente,
      feedbackFinalCoordenador: feedback.feedbackFinalCoordenador,
    });
    expect(reaberta.reaberturas).toHaveLength(1);
    expect(reaberta.reaberturas![0]).toMatchObject({
      motivo: "Corrigir lançamento",
      autorMatricula: gerente.matricula,
      autorNome: gerente.nome,
      data: expect.any(String),
    });
    expect(Number.isNaN(Date.parse(reaberta.reaberturas![0].data))).toBe(false);
    expect(getFeedbacks()).toEqual([reaberta]);

    const resource: EvaluationResource = {
      kind: "evaluation",
      evaluatedCollaborator: avaliado,
      collaborators: colaboradores,
      cycle: ciclo,
      evaluationStatus: reaberta.status,
    };
    expect(can(contexto(gerente), "evaluation.edit.manager", resource)).toBe(true);
    expect(can(contexto(coordenador), "evaluation.edit.coordinator", resource)).toBe(true);
    expect(can(contexto(colegiado), "evaluation.edit.board", resource)).toBe(true);
  });

  it("rejeita motivo vazio", () => {
    expect(() => reabrirAvaliacao(feedback.id, "   ", gerente)).toThrow(
      "Informe o motivo da reabertura."
    );
  });

  it.each([
    ["COORDENADOR", coordenador],
    ["COLEGIADO", colegiado],
    ["AVALIADO", avaliado],
  ] as const)("rejeita reabertura por %s", (_papel, actor) => {
    expect(() => reabrirAvaliacao(feedback.id, "Motivo válido", actor)).toThrow(
      AuthorizationError
    );
    expect(getFeedbacks()[0].status).toBe("CONCLUIDA");
  });

  it.each(["CANCELADA", "RASCUNHO", "PRONTA_PARA_FEEDBACK"] as const)(
    "rejeita avaliação com status %s",
    (status) => {
      localStorage.setItem(
        "feedback-control-feedbacks",
        JSON.stringify([{ ...feedback, status }])
      );

      expect(() =>
        reabrirAvaliacao(feedback.id, "Motivo válido", gerente)
      ).toThrow(AuthorizationError);
    }
  );

  it("rejeita reabertura quando o ciclo está encerrado", () => {
    localStorage.setItem(
      "feedback-control-ciclos",
      JSON.stringify([{ ...ciclo, status: "ENCERRADO" }])
    );

    expect(() =>
      reabrirAvaliacao(feedback.id, "Motivo válido", gerente)
    ).toThrow(AuthorizationError);
  });

  it("preserva todos os eventos após nova conclusão e múltiplas reaberturas", () => {
    const primeira = reabrirAvaliacao(feedback.id, "Primeira correção", gerente);
    updateFeedback({ ...primeira, status: "CONCLUIDA" });

    expect(getFeedbacks()[0].reaberturas).toEqual(primeira.reaberturas);

    const segunda = reabrirAvaliacao(feedback.id, "Segunda correção", gerente);
    expect(segunda.reaberturas).toHaveLength(2);
    expect(segunda.reaberturas?.map((evento) => evento.motivo)).toEqual([
      "Primeira correção",
      "Segunda correção",
    ]);
  });
});
