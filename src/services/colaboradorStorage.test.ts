import { beforeEach, describe, expect, it } from "vitest";
import type { Colaborador } from "../types/Colaborador";
import { colaboradores as colaboradoresIniciais } from "../data/colaboradores";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import {
  ERRO_ESCRITA_COLABORADOR_SOBERANA,
  getColaboradorByMatricula,
  getColaboradores,
  saveColaborador,
  updateColaborador,
} from "./colaboradorStorage";

/**
 * F5-07 (I7) — a leitura legada é PURA (não grava, não migra, não injeta
 * gestores) e a escrita é BARREIRA fail-closed (soberana no PostgreSQL).
 */
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

/** Registro no formato ANTIGO: sem `funcao`, sem `senioridade`, nome cru. */
function legado(): Colaborador {
  return {
    matricula: 99002,
    status: "ATIVO",
    nome: "PESSOA LEGADA",
    email: "pessoa.legada@example.com",
    cargo: "Analista Pleno Especialista",
    area: "Área Legada",
    respondePara: "",
  };
}

describe("colaboradorStorage (leitura pura e escrita soberana)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(STORAGE_KEY, "[]");
  });

  it("lê exatamente o registro existente, sem migrar, normalizar ou injetar gestores", () => {
    const antigo = legado();
    localStorage.setItem(STORAGE_KEY, JSON.stringify([antigo]));
    const antes = localStorage.getItem(STORAGE_KEY);

    const todos = getColaboradores();

    // Nada de formatação de nome, de inferência de `funcao`/`senioridade` por
    // cargo, nem de gestores sintéticos mesclados ao cadastro.
    expect(todos).toEqual([antigo]);
    expect(getColaboradorByMatricula(99002)).toEqual(antigo);
    expect(todos.some((item) => item.matricula === 900001)).toBe(false);
    // I7: a leitura NÃO escreve.
    expect(localStorage.getItem(STORAGE_KEY)).toBe(antes);
  });

  it("usa o seed sintético somente quando a chave não existe, sem regravá-la", () => {
    localStorage.removeItem(STORAGE_KEY);

    const seed = getColaboradores();

    expect(seed.length).toBeGreaterThan(0);
    expect(seed).toEqual(colaboradoresIniciais);
    // O caminho de leitura não persiste a fixture.
    expect(localStorage.getItem(STORAGE_KEY)).toBeNull();
  });

  it("saveColaborador é barreira fail-closed: lança e não grava", () => {
    const antes = localStorage.getItem(STORAGE_KEY);

    expect(() => saveColaborador(analista("Analista de Testes"))).toThrow(
      ERRO_ESCRITA_COLABORADOR_SOBERANA
    );
    expect(localStorage.getItem(STORAGE_KEY)).toBe(antes);
    expect(getColaboradorByMatricula(99001)).toBeUndefined();
  });

  it("updateColaborador é barreira fail-closed: lança e não altera o registro", () => {
    const antigo = legado();
    localStorage.setItem(STORAGE_KEY, JSON.stringify([antigo]));
    const antes = localStorage.getItem(STORAGE_KEY);

    expect(() =>
      updateColaborador({ ...antigo, status: "DESLIGADO" })
    ).toThrow(ERRO_ESCRITA_COLABORADOR_SOBERANA);
    expect(localStorage.getItem(STORAGE_KEY)).toBe(antes);
    expect(getColaboradorByMatricula(antigo.matricula)?.status).toBe("ATIVO");
  });

  it("propaga JSON inválido sem substituir os dados", () => {
    localStorage.setItem(STORAGE_KEY, "json inválido");

    expect(() => getColaboradores()).toThrow(SyntaxError);
    expect(localStorage.getItem(STORAGE_KEY)).toBe("json inválido");
  });
});
