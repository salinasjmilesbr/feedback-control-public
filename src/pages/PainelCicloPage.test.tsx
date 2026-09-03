import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Feedback, StatusFeedback } from "../types/Feedback";
import { obterAcaoAvaliacaoPainel } from "./painelCicloAvaliacaoAction";

function pessoa(matricula: number, funcao: Colaborador["funcao"], gestor?: number): Colaborador {
  return { matricula, funcao, gestorDiretoMatricula: gestor, status: "ATIVO", nome: `Pessoa ${matricula}`, email: `${matricula}@example.com`, cargo: "Cargo", area: "Área", respondePara: "" };
}

const gerente = pessoa(1, "GERENTE");
const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
const avaliado = pessoa(3, "ANALISTA", coordenador.matricula);
const colaboradores = [gerente, coordenador, avaliado];
const ciclo: CicloAvaliacao = { id: "ciclo", ano: 2026, ciclo: 1, status: "ATIVO", dataCriacao: "2026-01-01", dataUltimaAtualizacao: "2026-01-01" };

function feedback(status: StatusFeedback): Feedback {
  return { id: `feedback-${status}`, colaboradorId: avaliado.matricula, colaboradorNome: avaliado.nome, status, data: "2026-01-01", ano: 2026, ciclo: 1, competencias: [], notaMedia: 0 };
}

describe("ação de avaliação no painel do ciclo", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());
  it("abre edição somente quando há capability efetiva", () => {
    expect(obterAcaoAvaliacaoPainel(gerente, avaliado, colaboradores, ciclo, feedback("RASCUNHO"))).toEqual({ label: "Abrir avaliação", destino: "/colaborador/3/feedback/feedback-RASCUNHO/editar" });
  });

  it.each(["CONCLUIDA", "CANCELADA"] as const)("abre consulta, nunca /editar, para %s", (status) => {
    const acao = obterAcaoAvaliacaoPainel(gerente, avaliado, colaboradores, ciclo, feedback(status));
    expect(acao?.label).toBe("Ver avaliação");
    expect(acao?.destino).not.toContain("/editar");
  });

  it("abre consulta quando o ciclo está cancelado", () => {
    const acao = obterAcaoAvaliacaoPainel(gerente, avaliado, colaboradores, { ...ciclo, status: "CANCELADO" }, feedback("RASCUNHO"));
    expect(acao).toEqual({ label: "Ver avaliação", destino: "/colaborador/3/feedback/feedback-RASCUNHO" });
  });
});
