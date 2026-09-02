import { beforeEach, describe, expect, it } from "vitest";
import type { Colaborador } from "../types/Colaborador";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import {
  getColaboradorByMatricula,
  getColaboradores,
  saveColaborador,
  updateColaborador,
} from "./colaboradorStorage";

const STORAGE_KEY = "feedback-control-colaboradores";

function analista(cargo: string): Colaborador {
  return {
    matricula: 99001,
    status: "ATIVO",
    nome: "Pessoa Analista",
    email: "pessoa.analista@example.com",
    cargo,
    area: "Área de Testes",
    funcao: "ANALISTA",
    senioridade: "JUNIOR",
    respondePara: "",
  };
}

describe("colaboradorStorage", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(STORAGE_KEY, "[]");
  });

  it("preserva o cargo informado ao criar e ler um analista", () => {
    saveColaborador(analista("Analista de Testes"));

    expect(getColaboradorByMatricula(99001)?.cargo).toBe(
      "Analista de Testes"
    );
  });

  it("preserva o cargo informado ao editar e reler um analista", () => {
    saveColaborador(analista("Cargo Inicial"));
    updateColaborador(analista("Analista de Testes"));

    expect(getColaboradorByMatricula(99001)?.cargo).toBe(
      "Analista de Testes"
    );
  });

  it("continua migrando dados antigos sem inferir cargo pela matrícula", () => {
    const colaboradorAntigo: Colaborador = {
      matricula: 99002,
      status: "ATIVO",
      nome: "PESSOA LEGADA",
      email: "pessoa.legada@example.com",
      cargo: "Analista Pleno Especialista",
      area: "Área Legada",
      respondePara: "",
    };
    localStorage.setItem(STORAGE_KEY, JSON.stringify([colaboradorAntigo]));

    const migrado = getColaboradores().find(
      (colaborador) => colaborador.matricula === colaboradorAntigo.matricula
    );

    expect(migrado).toMatchObject({
      cargo: "Analista Pleno Especialista",
      funcao: "ANALISTA",
      senioridade: "PLENO",
    });
  });

  it("mantém o colaborador persistido ao alterar seu status para desligado", () => {
    const colaborador = analista("Analista de Testes");
    saveColaborador(colaborador);

    updateColaborador({ ...colaborador, status: "DESLIGADO" });

    expect(getColaboradorByMatricula(colaborador.matricula)).toMatchObject({
      matricula: colaborador.matricula,
      status: "DESLIGADO",
    });
  });
});
