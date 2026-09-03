import { beforeEach, describe, expect, it } from "vitest";
import { AuthorizationError } from "../authorization/authorizationError";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import {
  ativarCiclo,
  atualizarStatusCiclo,
  getCicloAtivo,
  getCiclosAdministrativos,
  getCiclosAvaliacao,
} from "./cicloAvaliacaoStorage";
import { cancelarCiclo } from "./cancelamentoCicloService";
import { gerarDadosTesteDoCiclo } from "./geradorDadosTeste";

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
const ativo: CicloAvaliacao = {
  id: "ciclo-ativo",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataInicio: "2026-01-01",
  dataFim: "2026-06-30",
  quantidadeMetasNegocio: 2,
  quantidadeMetasIndividuais: 1,
  dataCriacao: "2025-12-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};

describe("cancelarCiclo", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem("feedback-control-ciclos", JSON.stringify([ativo]));
  });

  it("permite ao gerente cancelar ciclo ativo com auditoria e preserva dados", () => {
    const feedbacks = [{ id: "avaliacao", conteudo: "preservado" }];
    const metas = [{ id: "meta", conteudo: "preservado" }];
    const observacoes = [{ id: "observacao", conteudo: "preservado" }];
    localStorage.setItem("feedback-control-feedbacks", JSON.stringify(feedbacks));
    localStorage.setItem("feedback-control-metas", JSON.stringify(metas));
    localStorage.setItem("feedback-control-observacoes", JSON.stringify(observacoes));

    const cancelado = cancelarCiclo(ativo.id, "  Interrupção necessária  ", gerente);

    expect(cancelado).toMatchObject({
      ...ativo,
      status: "CANCELADO",
      dataUltimaAtualizacao: expect.any(String),
      cancelamento: {
        motivo: "Interrupção necessária",
        autorMatricula: gerente.matricula,
        autorNome: gerente.nome,
        data: expect.any(String),
      },
    });
    expect(Number.isNaN(Date.parse(cancelado.cancelamento!.data))).toBe(false);
    expect(getCicloAtivo()).toBeUndefined();
    expect(JSON.parse(localStorage.getItem("feedback-control-feedbacks")!)).toEqual(feedbacks);
    expect(JSON.parse(localStorage.getItem("feedback-control-metas")!)).toEqual(metas);
    expect(JSON.parse(localStorage.getItem("feedback-control-observacoes")!)).toEqual(observacoes);
    expect(() => gerarDadosTesteDoCiclo(ativo, gerente)).toThrow(
      "Dados de ciclo cancelado não podem ser alterados."
    );
    expect(JSON.parse(localStorage.getItem("feedback-control-feedbacks")!)).toEqual(feedbacks);
    expect(JSON.parse(localStorage.getItem("feedback-control-metas")!)).toEqual(metas);
    expect(JSON.parse(localStorage.getItem("feedback-control-observacoes")!)).toEqual(observacoes);
  });

  it("rejeita não gerente e motivo vazio sem modificar o ciclo", () => {
    expect(() => cancelarCiclo(ativo.id, "Motivo", coordenador)).toThrow(
      AuthorizationError
    );
    expect(() => cancelarCiclo(ativo.id, "   ", gerente)).toThrow(
      "Informe o motivo do cancelamento do ciclo."
    );
    expect(getCiclosAvaliacao()).toEqual([ativo]);
  });

  it.each(["PLANEJADO", "ENCERRADO", "CANCELADO"] as const)(
    "rejeita cancelamento de ciclo %s",
    (status) => {
      localStorage.setItem(
        "feedback-control-ciclos",
        JSON.stringify([{ ...ativo, status }])
      );

      expect(() => cancelarCiclo(ativo.id, "Motivo", gerente)).toThrow(
        AuthorizationError
      );
      expect(getCiclosAvaliacao()[0].status).toBe(status);
    }
  );

  it("não permite alcançar CANCELADO por atualização genérica", () => {
    expect(() => atualizarStatusCiclo(ativo.id, "CANCELADO")).toThrow(
      "Transição de ciclo inválida"
    );
    expect(getCiclosAvaliacao()).toEqual([ativo]);
  });

  it("oculta cancelados por padrão e inclui por opção explícita", () => {
    cancelarCiclo(ativo.id, "Motivo", gerente);

    expect(getCiclosAdministrativos()).toEqual([]);
    expect(getCiclosAdministrativos(true)).toHaveLength(1);
    expect(getCiclosAdministrativos(true)[0].status).toBe("CANCELADO");
  });

  it("permite ativar outro ciclo planejado depois do cancelamento", () => {
    const planejado: CicloAvaliacao = {
      ...ativo,
      id: "ciclo-planejado",
      ciclo: 2,
      status: "PLANEJADO",
    };
    localStorage.setItem(
      "feedback-control-ciclos",
      JSON.stringify([ativo, planejado])
    );

    cancelarCiclo(ativo.id, "Motivo", gerente);
    ativarCiclo(planejado.id);

    expect(getCicloAtivo()?.id).toBe(planejado.id);
    expect(getCiclosAvaliacao().find((item) => item.id === ativo.id)?.status).toBe(
      "CANCELADO"
    );
  });
});
