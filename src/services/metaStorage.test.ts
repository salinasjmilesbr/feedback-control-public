import { beforeEach, describe, expect, it } from "vitest";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { podeAprovarMetaNoCiclo } from "./metaStorage";

function pessoa(
  matricula: number,
  funcao: Colaborador["funcao"],
  gestorDiretoMatricula?: number
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
    respondePara: "",
  };
}

const ciclo: CicloAvaliacao = {
  id: "ciclo-ativo",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataInicio: "2026-01-01",
  dataFim: "2026-12-31",
  dataCriacao: "2025-12-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};

describe("podeAprovarMetaNoCiclo", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  const gerente = pessoa(1, "GERENTE");
  const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
  const colaborador = pessoa(3, "ANALISTA", coordenador.matricula);
  const externo = pessoa(9, "COORDENADOR");
  const equipe = [gerente, coordenador, colaborador, externo];

  it("permite aprovação pelo coordenador direto", () => {
    expect(podeAprovarMetaNoCiclo(coordenador, colaborador, equipe, ciclo)).toBe(true);
  });

  it("permite aprovação pelo gerente responsável", () => {
    expect(podeAprovarMetaNoCiclo(gerente, colaborador, equipe, ciclo)).toBe(true);
  });

  it("nega aprovação a usuário fora da cadeia", () => {
    expect(podeAprovarMetaNoCiclo(externo, colaborador, equipe, ciclo)).toBe(false);
  });
});
