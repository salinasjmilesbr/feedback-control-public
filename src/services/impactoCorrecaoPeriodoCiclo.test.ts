import { describe, expect, it } from "vitest";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Feedback } from "../types/Feedback";
import type { Meta } from "../types/Meta";
import type { Observacao } from "../types/Observacao";
import { calcularImpactoCorrecaoPeriodo } from "./impactoCorrecaoPeriodoCiclo";

const ciclo: CicloAvaliacao = {
  id: "ciclo-ativo",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataInicio: "2026-01-01",
  dataFim: "2026-06-30",
  dataCriacao: "2025-12-01",
  dataUltimaAtualizacao: "2026-01-01",
};

function feedback(id: string, data: string, dataCriacao?: string): Feedback {
  return {
    id,
    colaboradorId: 2,
    colaboradorNome: "Pessoa Fictícia",
    status: "RASCUNHO",
    data,
    dataCriacao,
    dataUltimaAtualizacao: "2030-01-01T00:00:00.000Z",
    ano: 2026,
    ciclo: 1,
    competencias: [],
    notaMedia: 0,
  };
}

function meta(id: string, dataCriacao: string): Meta {
  return {
    id,
    colaboradorMatricula: 2,
    colaboradorNome: "Pessoa Fictícia",
    cicloId: ciclo.id,
    ano: ciclo.ano,
    ciclo: ciclo.ciclo,
    tipo: "INDIVIDUAL",
    descricao: id,
    kpi: "KPI",
    valorAlvo: "100",
    status: "EM_ANDAMENTO",
    dataCriacao,
    dataUltimaAtualizacao: "2030-01-01T00:00:00.000Z",
    excluida: id.includes("excluida"),
    historico: [],
  };
}

function observacao(id: string, dataCriacao: string): Observacao {
  return {
    id,
    colaboradorMatricula: 2,
    tipo: "NEUTRA",
    texto: id,
    comunicado: false,
    ano: ciclo.ano,
    ciclo: ciclo.ciclo,
    autorMatricula: 1,
    autorNome: "Gestor Fictício",
    dataCriacao,
    dataUltimaAtualizacao: "2030-01-01T00:00:00.000Z",
    excluida: id.includes("excluida"),
    historico: [],
  };
}

describe("impacto temporal da correção do período", () => {
  it("usa somente as datas originais, fallback legado e IDs determinísticos", () => {
    const impacto = calcularImpactoCorrecaoPeriodo(
      ciclo,
      "2026-02-01",
      "2026-05-31",
      [
        feedback("avaliacao-dentro", "2026-03-10", "2026-03-10T10:00:00Z"),
        feedback("avaliacao-fora-criacao", "2026-03-10", "2026-01-10T10:00:00Z"),
        feedback("avaliacao-legada", "2026-06-10"),
        feedback("avaliacao-fallback-invalido", "2026-01-05", "inválida"),
      ],
      [
        meta("meta-dentro", "2026-04-01T10:00:00Z"),
        meta("meta-excluida-fora", "2026-01-15T10:00:00Z"),
      ],
      [
        observacao("observacao-dentro", "2026-05-01T10:00:00Z"),
        observacao("observacao-excluida-fora", "2026-06-15T10:00:00Z"),
      ]
    );

    expect(impacto).toEqual({
      avaliacoes: {
        quantidade: 3,
        ids: [
          "avaliacao-fallback-invalido",
          "avaliacao-fora-criacao",
          "avaliacao-legada",
        ],
      },
      metas: { quantidade: 1, ids: ["meta-excluida-fora"] },
      observacoes: {
        quantidade: 1,
        ids: ["observacao-excluida-fora"],
      },
      total: 5,
    });
  });

  it("não considera dataUltimaAtualizacao nem registros dentro do período", () => {
    const impacto = calcularImpactoCorrecaoPeriodo(
      ciclo,
      "2026-01-01",
      "2026-06-30",
      [feedback("avaliacao", "2026-03-01", "2026-03-01")],
      [meta("meta-dentro", "2026-04-01")],
      [observacao("observacao-dentro", "2026-05-01")]
    );

    expect(impacto.total).toBe(0);
  });
});
