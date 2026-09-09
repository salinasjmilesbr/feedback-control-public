import { beforeEach, describe, expect, it } from "vitest";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { getRelatorioVisaoGeral } from "./relatorioService";

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
    area: "Área de teste",
    funcao,
    gestorDiretoMatricula,
    avaliadoresColegiadoMatriculas: colegiado,
    respondePara: "",
    dataAdmissao: "2020-01-01",
  };
}

const ciclo: CicloAvaliacao = {
  id: "relatorio-2026-1",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataInicio: "2026-01-01",
  dataFim: "2026-12-31",
  dataCriacao: "2025-12-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};

describe("getRelatorioVisaoGeral", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  it("restringe o relatório do coordenador à equipe direta e exclui participações apenas de colegiado", () => {
    const gerente = pessoa(900001, "GERENTE");
    const coordenador = pessoa(900002, "COORDENADOR", gerente.matricula);
    const outroCoordenador = pessoa(900003, "COORDENADOR", gerente.matricula);
    const terceiroCoordenador = pessoa(900004, "COORDENADOR", gerente.matricula);
    const direto = pessoa(10, "ANALISTA", coordenador.matricula);
    const apenasColegiado = pessoa(
      11,
      "ANALISTA",
      outroCoordenador.matricula,
      [coordenador.matricula]
    );
    const colaboradores = [
      gerente,
      coordenador,
      outroCoordenador,
      terceiroCoordenador,
      direto,
      apenasColegiado,
    ];
    localStorage.setItem(
      "feedback-control-colaboradores",
      JSON.stringify(colaboradores)
    );
    localStorage.setItem("feedback-control-feedbacks", "[]");

    const relatorio = getRelatorioVisaoGeral(ciclo, coordenador);

    expect(relatorio.colaboradores.map(({ matricula }) => matricula)).toEqual([10]);
    expect(relatorio.totalElegiveis).toBe(1);
  });

  it("oculta canceladas por padrão e inclui por filtro explícito", () => {
    const gerente = pessoa(900001, "GERENTE");
    const avaliado = pessoa(10, "CONSULTOR", gerente.matricula);
    const cancelada: Feedback = {
      id: "cancelada-relatorio",
      colaboradorId: avaliado.matricula,
      colaboradorNome: avaliado.nome,
      status: "CANCELADA",
      data: "2026-01-10T00:00:00.000Z",
      ano: ciclo.ano,
      ciclo: ciclo.ciclo,
      notaMedia: 4,
      competencias: [],
    };
    localStorage.setItem(
      "feedback-control-colaboradores",
      JSON.stringify([gerente, avaliado])
    );
    localStorage.setItem(
      "feedback-control-feedbacks",
      JSON.stringify([cancelada])
    );

    expect(
      getRelatorioVisaoGeral(ciclo, gerente).colaboradores.some(
        (item) => item.matricula === avaliado.matricula
      )
    ).toBe(false);

    const incluindo = getRelatorioVisaoGeral(ciclo, gerente, {
      incluirCanceladas: true,
    });
    expect(
      incluindo.colaboradores.find(
        (item) => item.matricula === avaliado.matricula
      )?.situacao
    ).toBe("CANCELADA");
  });

  it("LIMIT → THEN → AGGREGATE: agregações usam apenas o dataset autorizado (não vaza nota de fora do escopo)", () => {
    // Coordenador consolida somente sua equipe direta. Se a implementação
    // agregar ANTES de limitar, a nota 5 de "fora" contaminaria a média.
    const gerente = pessoa(900001, "GERENTE");
    const coordenador = pessoa(900002, "COORDENADOR", gerente.matricula);
    const direto = pessoa(10, "ANALISTA", coordenador.matricula);
    const fora = pessoa(12, "ANALISTA", gerente.matricula); // irmão, fora do scope do coordenador
    const colaboradores = [gerente, coordenador, direto, fora];

    const feedbackDireto: Feedback = {
      id: "fb-direto",
      colaboradorId: direto.matricula,
      colaboradorNome: direto.nome,
      status: "CONCLUIDA",
      data: "2026-03-01T00:00:00.000Z",
      ano: ciclo.ano,
      ciclo: ciclo.ciclo,
      notaMedia: 2,
      competencias: [],
    };
    const feedbackFora: Feedback = {
      id: "fb-fora",
      colaboradorId: fora.matricula,
      colaboradorNome: fora.nome,
      status: "CONCLUIDA",
      data: "2026-03-01T00:00:00.000Z",
      ano: ciclo.ano,
      ciclo: ciclo.ciclo,
      notaMedia: 5,
      competencias: [],
    };

    localStorage.setItem(
      "feedback-control-colaboradores",
      JSON.stringify(colaboradores)
    );
    localStorage.setItem(
      "feedback-control-feedbacks",
      JSON.stringify([feedbackDireto, feedbackFora])
    );

    const relatorio = getRelatorioVisaoGeral(ciclo, coordenador);

    // 1) dataset limitado primeiro: só o direto entra (contagem).
    expect(relatorio.colaboradores.map(({ matricula }) => matricula)).toEqual([
      direto.matricula,
    ]);
    expect(relatorio.totalElegiveis).toBe(1);
    expect(relatorio.avaliacoesComNota).toBe(1);

    // 2) agregações calculadas DEPOIS, só sobre o autorizado: média = 2 (não 3,5).
    expect(relatorio.mediaEquipe).toBe(2);

    // 3) distribuição não contém a nota 5 de "fora".
    const quantidades = relatorio.distribuicao.map((item) => item.quantidade);
    expect(quantidades.reduce((soma, q) => soma + q, 0)).toBe(1);
  });
});
