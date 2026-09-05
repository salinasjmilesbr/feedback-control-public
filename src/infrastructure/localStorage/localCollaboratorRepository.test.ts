import { beforeEach, describe, expect, it } from "vitest";
import type { CollaboratorRepository } from "../../application/ports/CollaboratorRepository";
import { getColaboradorByMatricula, saveColaborador } from "../../services/colaboradorStorage";
import { instalarLocalStorageEmMemoria } from "../../test/localStorageMock";
import type { Colaborador } from "../../types/Colaborador";
import { localCollaboratorRepository } from "./localCollaboratorRepository";

const STORAGE_KEY = "feedback-control-colaboradores";
const repository: CollaboratorRepository = localCollaboratorRepository;

function colaborador(): Colaborador {
  return {
    matricula: 99001,
    status: "ATIVO",
    nome: "Pessoa de Teste",
    email: "pessoa@example.invalid",
    cargo: "Analista Pleno de Testes",
    area: "Área Fictícia",
    respondePara: "",
  };
}

describe("CollaboratorRepository com storage local", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(STORAGE_KEY, "[]");
  });

  it("mantém migração de cadastro legado e grava a mesma base normalizada", () => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify([{ ...colaborador(), nome: " PESSOA DE TESTE " }]));

    const todos = repository.getColaboradores();

    expect(todos.find((item) => item.matricula === 99001)).toMatchObject({
      nome: "Pessoa de Teste", funcao: "ANALISTA", senioridade: "PLENO", cargo: "Analista Pleno de Testes",
    });
    expect(todos.some((item) => item.funcao === "GERENTE")).toBe(true);
    expect(JSON.parse(localStorage.getItem(STORAGE_KEY)!)).toEqual(todos);
    expect(repository.getColaboradorByMatricula(-1)).toBeUndefined();
  });

  it("compartilha gravações com o storage atual e preserva matrícula e desligamento", () => {
    repository.saveColaborador(colaborador());
    expect(getColaboradorByMatricula(99001)?.cargo).toBe("Analista Pleno de Testes");
    saveColaborador({ ...colaborador(), matricula: 99002 });
    expect(repository.getColaboradorByMatricula(99002)).toBeDefined();

    repository.updateColaborador({ ...colaborador(), cargo: "Cargo Editado", status: "DESLIGADO" });

    expect(getColaboradorByMatricula(99001)).toMatchObject({ matricula: 99001, cargo: "Cargo Editado", status: "DESLIGADO" });
    expect(JSON.parse(localStorage.getItem(STORAGE_KEY)!)).toContainEqual(repository.getColaboradorByMatricula(99001));
  });

  it("rejeita matrícula duplicada sem substituir o cadastro persistido", () => {
    repository.saveColaborador(colaborador());
    repository.getColaboradores();
    const antes = localStorage.getItem(STORAGE_KEY);

    expect(() => repository.saveColaborador({ ...colaborador(), nome: "Outra Pessoa" }))
      .toThrow("Já existe um colaborador com esta matrícula.");
    expect(localStorage.getItem(STORAGE_KEY)).toBe(antes);
  });

  it("atualizar matrícula inexistente não cria cadastro nem altera histórico organizacional", () => {
    const chaveHistorico = "feedback-control-historico-organizacional";
    const historico = '[{"id":"registro-ficticio-preservado"}]';
    localStorage.setItem(chaveHistorico, historico);
    repository.getColaboradores();
    const antes = localStorage.getItem(STORAGE_KEY);

    repository.updateColaborador(colaborador());

    expect(repository.getColaboradorByMatricula(99001)).toBeUndefined();
    expect(localStorage.getItem(STORAGE_KEY)).toBe(antes);
    expect(localStorage.getItem(chaveHistorico)).toBe(historico);
  });

  it("propaga erro de JSON inválido sem substituir dados, como o storage atual", () => {
    localStorage.setItem(STORAGE_KEY, "json inválido");

    expect(() => repository.getColaboradores()).toThrow(SyntaxError);
    expect(localStorage.getItem(STORAGE_KEY)).toBe("json inválido");
  });
});
