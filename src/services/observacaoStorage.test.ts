import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Observacao } from "../types/Observacao";
import {
  atualizarObservacao,
  criarObservacao,
  excluirObservacao,
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
