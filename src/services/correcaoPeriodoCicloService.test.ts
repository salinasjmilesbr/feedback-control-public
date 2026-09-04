import { beforeEach, describe, expect, it } from "vitest";
import { AuthorizationError } from "../authorization/authorizationError";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import type { Meta } from "../types/Meta";
import type { Observacao } from "../types/Observacao";
import { getCiclosAvaliacao } from "./cicloAvaliacaoStorage";
import {
  analisarImpactoCorrecaoPeriodoCicloAtivo,
  corrigirPeriodoCicloAtivo,
} from "./correcaoPeriodoCicloService";

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
const coordenador: Colaborador = {
  ...gerente,
  matricula: 2,
  nome: "Coordenador Fictício",
  email: "coordenador@example.com",
  funcao: "COORDENADOR",
};
const cicloAtivo: CicloAvaliacao = {
  id: "ciclo-ativo",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataInicio: "2026-01-01",
  dataFim: "2026-06-30",
  dataCriacao: "2025-12-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
  dataAtivacao: "2026-01-01T00:00:00.000Z",
};

function persistirCiclo(ciclo: CicloAvaliacao) {
  localStorage.setItem("feedback-control-ciclos", JSON.stringify([ciclo]));
}

describe("corrigirPeriodoCicloAtivo", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    persistirCiclo(cicloAtivo);
  });

  it.each([
    ["somente o início", "2026-02-01", "2026-06-30"],
    ["somente o fim", "2026-01-01", "2026-05-31"],
    ["início e fim", "2026-02-01", "2026-05-31"],
  ])("permite alterar %s", (_cenario, dataInicio, dataFim) => {
    const corrigido = corrigirPeriodoCicloAtivo(
      cicloAtivo.id,
      dataInicio,
      dataFim,
      "  Correção necessária  ",
      gerente
    );

    expect(corrigido).toMatchObject({
      status: "ATIVO",
      dataInicio,
      dataFim,
      correcoesPeriodo: [
        {
          periodoAnterior: {
            dataInicio: cicloAtivo.dataInicio,
            dataFim: cicloAtivo.dataFim,
          },
          novoPeriodo: { dataInicio, dataFim },
          justificativa: "Correção necessária",
          autorMatricula: gerente.matricula,
          autorNome: gerente.nome,
          data: expect.any(String),
        },
      ],
    });
    expect(Number.isNaN(Date.parse(corrigido.correcoesPeriodo![0].data))).toBe(
      false
    );
  });

  it("rejeita perfil não autorizado e estados inelegíveis sem alteração", () => {
    const antes = localStorage.getItem("feedback-control-ciclos");
    expect(() =>
      corrigirPeriodoCicloAtivo(
        cicloAtivo.id,
        "2026-02-01",
        "2026-06-30",
        "Motivo",
        coordenador
      )
    ).toThrow(AuthorizationError);
    expect(localStorage.getItem("feedback-control-ciclos")).toBe(antes);

    for (const status of ["PLANEJADO", "ENCERRADO", "CANCELADO"] as const) {
      const ciclo = { ...cicloAtivo, status };
      persistirCiclo(ciclo);
      const persistido = localStorage.getItem("feedback-control-ciclos");
      expect(() =>
        corrigirPeriodoCicloAtivo(
          ciclo.id,
          "2026-02-01",
          "2026-06-30",
          "Motivo",
          gerente
        )
      ).toThrow("Somente ciclos ativos podem ter o período corrigido.");
      expect(localStorage.getItem("feedback-control-ciclos")).toBe(persistido);
    }
  });

  it("rejeita período inválido, justificativa vazia e ausência de alteração", () => {
    const antes = localStorage.getItem("feedback-control-ciclos");
    expect(() =>
      corrigirPeriodoCicloAtivo(
        cicloAtivo.id,
        "2026-07-01",
        "2026-06-30",
        "Motivo",
        gerente
      )
    ).toThrow("A data de início não pode ser posterior à data de fim.");
    expect(() =>
      corrigirPeriodoCicloAtivo(
        cicloAtivo.id,
        "2026-02-01",
        "2026-06-30",
        "   ",
        gerente
      )
    ).toThrow("Informe a justificativa da correção do período.");
    expect(() =>
      corrigirPeriodoCicloAtivo(
        cicloAtivo.id,
        cicloAtivo.dataInicio!,
        cicloAtivo.dataFim!,
        "Motivo",
        gerente
      )
    ).toThrow("Informe um período diferente do período atual.");
    expect(localStorage.getItem("feedback-control-ciclos")).toBe(antes);
  });

  it("persiste snapshot e preserva integralmente os registros vinculados", () => {
    const avaliacao: Feedback = {
      id: "avaliacao-cancelada",
      colaboradorId: 3,
      colaboradorNome: "Pessoa Fictícia",
      status: "CANCELADA",
      data: "2026-01-10",
      dataCriacao: "2026-01-10T10:00:00.000Z",
      ano: 2026,
      ciclo: 1,
      competencias: [],
      notaMedia: 0,
    };
    const meta: Meta = {
      id: "meta-excluida",
      colaboradorMatricula: 3,
      colaboradorNome: "Pessoa Fictícia",
      cicloId: cicloAtivo.id,
      ano: 2026,
      ciclo: 1,
      tipo: "INDIVIDUAL",
      descricao: "Meta preservada",
      kpi: "KPI",
      valorAlvo: "100",
      status: "EM_ANDAMENTO",
      dataCriacao: "2026-07-10T10:00:00.000Z",
      dataUltimaAtualizacao: "2026-07-10T10:00:00.000Z",
      excluida: true,
      historico: [],
    };
    const observacao: Observacao = {
      id: "observacao-excluida",
      colaboradorMatricula: 3,
      tipo: "NEUTRA",
      texto: "Observação preservada",
      comunicado: false,
      ano: 2026,
      ciclo: 1,
      autorMatricula: 1,
      autorNome: gerente.nome,
      dataCriacao: "2026-03-10T10:00:00.000Z",
      dataUltimaAtualizacao: "2030-01-01T00:00:00.000Z",
      excluida: true,
      historico: [],
    };
    localStorage.setItem("feedback-control-feedbacks", JSON.stringify([avaliacao]));
    localStorage.setItem("feedback-control-metas", JSON.stringify([meta]));
    localStorage.setItem("feedback-control-observacoes", JSON.stringify([observacao]));
    const relacionadosAntes = {
      feedbacks: localStorage.getItem("feedback-control-feedbacks"),
      metas: localStorage.getItem("feedback-control-metas"),
      observacoes: localStorage.getItem("feedback-control-observacoes"),
    };

    const impacto = analisarImpactoCorrecaoPeriodoCicloAtivo(
      cicloAtivo.id,
      "2026-02-01",
      "2026-05-31"
    );
    expect(impacto).toEqual({
      avaliacoes: { quantidade: 1, ids: [avaliacao.id] },
      metas: { quantidade: 1, ids: [meta.id] },
      observacoes: { quantidade: 0, ids: [] },
      total: 2,
    });

    const corrigido = corrigirPeriodoCicloAtivo(
      cicloAtivo.id,
      "2026-02-01",
      "2026-05-31",
      "Ajustar período",
      gerente
    );
    expect(corrigido.correcoesPeriodo![0].impacto).toEqual(impacto);
    expect(corrigido.status).toBe("ATIVO");
    expect(localStorage.getItem("feedback-control-feedbacks")).toBe(
      relacionadosAntes.feedbacks
    );
    expect(localStorage.getItem("feedback-control-metas")).toBe(
      relacionadosAntes.metas
    );
    expect(localStorage.getItem("feedback-control-observacoes")).toBe(
      relacionadosAntes.observacoes
    );
  });

  it("acumula correções sem sobrescrever eventos anteriores", () => {
    corrigirPeriodoCicloAtivo(
      cicloAtivo.id,
      "2026-02-01",
      "2026-06-30",
      "Primeira correção",
      gerente
    );
    const corrigido = corrigirPeriodoCicloAtivo(
      cicloAtivo.id,
      "2026-02-01",
      "2026-05-31",
      "Segunda correção",
      gerente
    );

    expect(corrigido.correcoesPeriodo).toHaveLength(2);
    expect(corrigido.correcoesPeriodo?.map((evento) => evento.justificativa)).toEqual([
      "Primeira correção",
      "Segunda correção",
    ]);
    expect(corrigido.correcoesPeriodo?.[1].periodoAnterior).toEqual({
      dataInicio: "2026-02-01",
      dataFim: "2026-06-30",
    });
    expect(getCiclosAvaliacao()[0].correcoesPeriodo).toEqual(
      corrigido.correcoesPeriodo
    );
  });
});
