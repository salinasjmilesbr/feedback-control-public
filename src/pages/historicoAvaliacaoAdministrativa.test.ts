import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";
import {
  getAcaoConsultaHistoricoAdministrativo,
  ordenarHistoricoAdministrativo,
} from "./historicoAvaliacaoAdministrativa";

const gerente: Colaborador = { matricula: 1, nome: "Gerente", email: "gerente@example.com", cargo: "Gerente", area: "Área", funcao: "GERENTE", status: "ATIVO", respondePara: "" };
const avaliado: Colaborador = { matricula: 2, nome: "Avaliado", email: "avaliado@example.com", cargo: "Analista", area: "Área", funcao: "ANALISTA", status: "ATIVO", gestorDiretoMatricula: 1, respondePara: "" };
const colaboradores = [gerente, avaliado];
const ciclo: CicloAvaliacao = { id: "ciclo", ano: 2027, ciclo: 2, status: "ENCERRADO", dataCriacao: "2027-01-01", dataUltimaAtualizacao: "2027-01-01" };

function feedback(id: string, ano: number, numero: 1 | 2 | 3, status: Feedback["status"]): Feedback {
  return { id, ano, ciclo: numero, status, colaboradorId: 2, colaboradorNome: "Avaliado", data: "2020-01-01", competencias: [], notaMedia: 0 };
}

describe("histórico administrativo de avaliações", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  it("ordena estados mistos por ano e ciclo em Mais recentes", () => {
    const ordenados = ordenarHistoricoAdministrativo([
      feedback("cancelado-2027-1", 2027, 1, "CANCELADA"),
      feedback("concluido-2026-3", 2026, 3, "CONCLUIDA"),
      feedback("concluido-2027-2", 2027, 2, "CONCLUIDA"),
      feedback("rascunho-2026-2", 2026, 2, "RASCUNHO"),
    ], "RECENTES");
    expect(ordenados.map((item) => `${item.ano}-${item.ciclo}`)).toEqual([
      "2027-2", "2027-1", "2026-3", "2026-2",
    ]);
  });

  it("preserva a opção Mais antigas", () => {
    const ordenados = ordenarHistoricoAdministrativo([
      feedback("novo", 2027, 2, "CONCLUIDA"),
      feedback("antigo", 2026, 1, "CONCLUIDA"),
    ], "ANTIGAS");
    expect(ordenados.map((item) => item.id)).toEqual(["antigo", "novo"]);
  });

  it("usa Ver avaliação para item administrativo somente de consulta", () => {
    expect(getAcaoConsultaHistoricoAdministrativo(
      gerente,
      avaliado,
      colaboradores,
      ciclo,
      feedback("rascunho", 2027, 2, "RASCUNHO")
    )).toEqual({
      label: "Ver avaliação",
      destino: "/colaborador/2/feedback/rascunho",
    });
  });

  it("não cria ação que levaria usuário sem consulta a acesso restrito", () => {
    expect(getAcaoConsultaHistoricoAdministrativo(
      avaliado,
      avaliado,
      colaboradores,
      ciclo,
      feedback("rascunho", 2027, 2, "RASCUNHO")
    )).toBeUndefined();
  });
});
