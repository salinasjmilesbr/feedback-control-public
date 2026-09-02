import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type {
  CicloAvaliacao,
  StatusCicloAvaliacao,
} from "../types/CicloAvaliacao";
import {
  ativarCiclo,
  atualizarPeriodoCiclo,
  atualizarStatusCiclo,
  encerrarCiclo,
  getCiclosAvaliacao,
} from "./cicloAvaliacaoStorage";

const STORAGE_KEY = "feedback-control-ciclos";

function ciclo(
  id: string,
  status: StatusCicloAvaliacao,
  numero: 1 | 2 | 3 = 1
): CicloAvaliacao {
  return {
    id,
    ano: 2026,
    ciclo: numero,
    status,
    dataInicio: "2026-01-01",
    dataFim: "2026-06-30",
    dataCriacao: "2026-01-01T00:00:00.000Z",
    dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
  };
}

function persistir(...ciclos: CicloAvaliacao[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(ciclos));
}

function status(id: string): StatusCicloAvaliacao | undefined {
  return getCiclosAvaliacao().find((item) => item.id === id)?.status;
}

describe("lifecycle normal de ciclos", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  it("permite PLANEJADO → ATIVO", () => {
    persistir(ciclo("planejado", "PLANEJADO"));

    ativarCiclo("planejado");

    expect(status("planejado")).toBe("ATIVO");
  });

  it("permite ATIVO → ENCERRADO", () => {
    persistir(ciclo("ativo", "ATIVO"));

    encerrarCiclo("ativo", 2);

    expect(getCiclosAvaliacao()[0]).toMatchObject({
      status: "ENCERRADO",
      encerradoComPendencias: true,
      quantidadePendencias: 2,
    });
  });

  it.each(["ATIVO", "ENCERRADO"] as const)("rejeita ativar ciclo %s", (statusAtual) => {
    persistir(ciclo("alvo", statusAtual));

    expect(() => ativarCiclo("alvo")).toThrow("Transição de ciclo inválida");
    expect(status("alvo")).toBe(statusAtual);
  });

  it.each(["PLANEJADO", "ENCERRADO"] as const)("rejeita encerrar ciclo %s", (statusAtual) => {
    persistir(ciclo("alvo", statusAtual));

    expect(() => encerrarCiclo("alvo")).toThrow("Transição de ciclo inválida");
    expect(status("alvo")).toBe(statusAtual);
  });

  it.each([
    ["ATIVO", "PLANEJADO"],
    ["ENCERRADO", "PLANEJADO"],
    ["ENCERRADO", "ATIVO"],
  ] as const)(
    "rejeita atualização genérica %s → %s",
    (statusAtual, novoStatus) => {
      persistir(ciclo("alvo", statusAtual));

      expect(() => atualizarStatusCiclo("alvo", novoStatus)).toThrow(
        "Transição de ciclo inválida"
      );
      expect(status("alvo")).toBe(statusAtual);
    }
  );

  it("mantém no máximo um ciclo ATIVO", () => {
    persistir(ciclo("ativo", "ATIVO"), ciclo("planejado", "PLANEJADO", 2));

    expect(() => ativarCiclo("planejado")).toThrow("Já existe um ciclo ativo");
    expect(status("ativo")).toBe("ATIVO");
    expect(status("planejado")).toBe("PLANEJADO");
  });
});

describe("edição normal do período do ciclo", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  it("permite alterar o período de ciclo planejado", () => {
    persistir(ciclo("planejado", "PLANEJADO"));

    atualizarPeriodoCiclo("planejado", "2026-02-01", "2026-07-31");

    expect(getCiclosAvaliacao()[0]).toMatchObject({
      dataInicio: "2026-02-01",
      dataFim: "2026-07-31",
    });
  });

  it.each(["ATIVO", "ENCERRADO"] as const)(
    "rejeita alteração direta em ciclo %s sem modificar nenhum dado",
    (statusAtual) => {
      const original = ciclo("alvo", statusAtual);
      persistir(original);

      expect(() =>
        atualizarPeriodoCiclo("alvo", "2026-02-01", "2026-07-31")
      ).toThrow("O período só pode ser alterado enquanto o ciclo estiver Planejado.");
      expect(getCiclosAvaliacao()).toEqual([original]);
    }
  );

  it.each([
    ["", "2026-07-31"],
    ["2026-02-01", ""],
  ] as const)("mantém as duas datas obrigatórias", (dataInicio, dataFim) => {
    const original = ciclo("planejado", "PLANEJADO");
    persistir(original);

    expect(() =>
      atualizarPeriodoCiclo("planejado", dataInicio, dataFim)
    ).toThrow("Informe as datas de início e fim do ciclo.");
    expect(getCiclosAvaliacao()).toEqual([original]);
  });

  it("rejeita data inicial posterior à final sem modificar o ciclo", () => {
    const original = ciclo("planejado", "PLANEJADO");
    persistir(original);

    expect(() =>
      atualizarPeriodoCiclo("planejado", "2026-08-01", "2026-07-31")
    ).toThrow("A data de início não pode ser posterior à data de fim.");
    expect(getCiclosAvaliacao()).toEqual([original]);
  });
});
