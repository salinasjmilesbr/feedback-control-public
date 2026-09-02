import { beforeEach, describe, expect, it } from "vitest";
import { AuthorizationError } from "../authorization/authorizationError";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import { cancelarAvaliacao } from "./cancelamentoAvaliacaoService";
import { getFeedbacks } from "./feedbackStorage";

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
  id: "ciclo-cancelamento",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};
const feedback: Feedback = {
  id: "avaliacao-cancelamento",
  colaboradorId: avaliado.matricula,
  colaboradorNome: avaliado.nome,
  status: "RASCUNHO",
  data: "2026-01-10T00:00:00.000Z",
  ano: 2026,
  ciclo: 1,
  notaMedia: 4,
  competencias: [
    {
      competenciaId: "qualidade",
      competenciaNome: "Qualidade",
      nota: 4,
      comentario: "Conteúdo preservado",
    },
  ],
  feedbackFinalGerente: "Registro anterior",
};

describe("cancelarAvaliacao", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem("feedback-control-colaboradores", JSON.stringify(colaboradores));
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([ciclo]));
    localStorage.setItem("feedback-control-feedbacks", JSON.stringify([feedback]));
  });

  it("permite ao gerente responsável cancelar com auditoria e preserva dados", () => {
    const cancelada = cancelarAvaliacao(feedback.id, "  Não se aplica mais  ", gerente);

    expect(cancelada).toMatchObject({
      status: "CANCELADA",
      motivoCancelamento: "Não se aplica mais",
      canceladoPorMatricula: gerente.matricula,
      canceladoPorNome: gerente.nome,
      notaMedia: feedback.notaMedia,
      competencias: feedback.competencias,
      feedbackFinalGerente: feedback.feedbackFinalGerente,
    });
    expect(cancelada.dataCancelamento).toEqual(expect.any(String));
    expect(Number.isNaN(Date.parse(cancelada.dataCancelamento!))).toBe(false);
    expect(getFeedbacks()).toHaveLength(1);
  });

  it("rejeita cancelamento sem motivo", () => {
    expect(() => cancelarAvaliacao(feedback.id, "   ", gerente)).toThrow(
      "Informe o motivo do cancelamento."
    );
  });

  it.each([
    ["COORDENADOR", coordenador],
    ["COLEGIADO", colegiado],
    ["AVALIADO", avaliado],
  ] as const)("rejeita cancelamento por %s", (_papel, actor) => {
    expect(() => cancelarAvaliacao(feedback.id, "Motivo válido", actor)).toThrow(
      AuthorizationError
    );
    expect(getFeedbacks()[0].status).toBe("RASCUNHO");
  });
});
