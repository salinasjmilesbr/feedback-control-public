import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Observacao } from "../types/Observacao";
import {
  atualizarObservacao,
  criarObservacao,
  excluirObservacao,
  getObservacoesByColaborador,
} from "./observacaoStorage";

const autor: Colaborador = {
  matricula: 1,
  status: "ATIVO",
  nome: "Gestor Fictício",
  email: "gestor@example.com",
  cargo: "Gerente",
  area: "Área fictícia",
  funcao: "GERENTE",
  respondePara: "",
};
const cicloCancelado: CicloAvaliacao = {
  id: "ciclo-cancelado",
  ano: 2026,
  ciclo: 1,
  status: "CANCELADO",
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};
const observacao: Observacao = {
  id: "observacao-preservada",
  colaboradorMatricula: 2,
  tipo: "NEUTRA",
  texto: "Conteúdo preservado",
  comunicado: false,
  ano: cicloCancelado.ano,
  ciclo: cicloCancelado.ciclo,
  autorMatricula: autor.matricula,
  autorNome: autor.nome,
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
  excluida: false,
  historico: [],
};

describe("observações de ciclo cancelado", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      "feedback-control-ciclos",
      JSON.stringify([cicloCancelado])
    );
    localStorage.setItem(
      "feedback-control-observacoes",
      JSON.stringify([observacao])
    );
  });

  it("rejeita criação, edição e exclusão sem modificar observações", () => {
    const operacoes = [
      () =>
        criarObservacao(
          2,
          "POSITIVA",
          "Nova",
          false,
          cicloCancelado.ano,
          cicloCancelado.ciclo,
          autor
        ),
      () =>
        atualizarObservacao(
          observacao.id,
          "POSITIVA",
          "Alterada",
          true,
          cicloCancelado.ano,
          cicloCancelado.ciclo,
          autor
        ),
      () => excluirObservacao(observacao.id, autor),
    ];

    operacoes.forEach((operacao) =>
      expect(operacao).toThrow(
        "Observações de ciclo cancelado não podem ser alteradas."
      )
    );
    expect(
      JSON.parse(localStorage.getItem("feedback-control-observacoes")!)
    ).toEqual([observacao]);
  });
});

describe("ordenação do histórico de observações", () => {
  const criarItem = (
    id: string,
    ano: number,
    ciclo: 1 | 2 | 3,
    tipo: Observacao["tipo"],
    excluida = false
  ): Observacao => ({
    ...observacao,
    id,
    ano,
    ciclo,
    tipo,
    excluida,
    texto: id,
  });

  beforeEach(() => instalarLocalStorageEmMemoria());

  it("ordena globalmente por ano e ciclo em Mais recentes, independentemente do tipo", () => {
    const itens = [
      criarItem("negativa-2026-3", 2026, 3, "NEGATIVA"),
      criarItem("positiva-2027-1", 2027, 1, "POSITIVA"),
      criarItem("neutra-2026-1", 2026, 1, "NEUTRA"),
      criarItem("negativa-2027-2", 2027, 2, "NEGATIVA"),
      criarItem("positiva-2026-2", 2026, 2, "POSITIVA"),
    ];
    localStorage.setItem("feedback-control-observacoes", JSON.stringify(itens));

    expect(
      getObservacoesByColaborador(2).map((item) => `${item.ano}-${item.ciclo}`)
    ).toEqual(["2027-2", "2027-1", "2026-3", "2026-2", "2026-1"]);
  });

  it("suporta a ordem inversa por ano e ciclo em Mais antigas", () => {
    const itens = [
      criarItem("novo", 2027, 2, "NEUTRA"),
      criarItem("intermediario", 2027, 1, "POSITIVA"),
      criarItem("antigo", 2026, 3, "NEGATIVA"),
    ];
    localStorage.setItem("feedback-control-observacoes", JSON.stringify(itens));

    expect(
      getObservacoesByColaborador(2, false, "ANTIGAS").map((item) => item.id)
    ).toEqual(["antigo", "intermediario", "novo"]);
  });

  it("preserva filtros e não modifica os dados persistidos", () => {
    const itens = [
      criarItem("visivel", 2026, 1, "NEUTRA"),
      criarItem("excluida", 2027, 2, "POSITIVA", true),
      {
        ...criarItem("outro-colaborador", 2028, 3, "NEGATIVA"),
        colaboradorMatricula: 99,
      },
    ];
    const persistido = JSON.stringify(itens);
    localStorage.setItem("feedback-control-observacoes", persistido);

    expect(getObservacoesByColaborador(2).map((item) => item.id)).toEqual([
      "visivel",
    ]);
    expect(
      getObservacoesByColaborador(2, true).map((item) => item.id)
    ).toEqual(["excluida", "visivel"]);
    expect(localStorage.getItem("feedback-control-observacoes")).toBe(
      persistido
    );
  });
});
