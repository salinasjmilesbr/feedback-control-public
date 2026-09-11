import { beforeEach, describe, expect, it } from "vitest";
import type { CollaboratorRepository } from "../../application/ports/CollaboratorRepository";
import {
  ERRO_ESCRITA_COLABORADOR_SOBERANA,
  getColaboradorByMatricula,
} from "../../services/colaboradorStorage";
import { instalarLocalStorageEmMemoria } from "../../test/localStorageMock";
import type { Colaborador } from "../../types/Colaborador";
import { localCollaboratorRepository } from "./localCollaboratorRepository";

/**
 * F5-07 — o adapter de `localStorage` NÃO é o caminho de produção: o port
 * `CollaboratorRepository` é servido pela implementação soberana
 * (`src/services/colaboradoresSoberanos`). Aqui só se garante o contrato DEV:
 * leitura pura (sem normalização/injeção) e escrita sempre barrada.
 */
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

describe("CollaboratorRepository com storage local (adapter DEV/legado)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(STORAGE_KEY, "[]");
  });

  it("lê o cadastro legado sem migrar, normalizar nem injetar gestores", () => {
    const legado = { ...colaborador(), nome: " PESSOA DE TESTE " };
    localStorage.setItem(STORAGE_KEY, JSON.stringify([legado]));
    const antes = localStorage.getItem(STORAGE_KEY);

    const todos = repository.getColaboradores();

    expect(todos.find((item) => item.matricula === 99001)).toEqual(legado);
    // Sem `funcao`/`senioridade` inferidos e sem gestores sintéticos.
    expect(todos.some((item) => item.funcao === "GERENTE")).toBe(false);
    expect(todos).toHaveLength(1);
    expect(repository.getColaboradorByMatricula(-1)).toBeUndefined();
    // I7: a leitura não grava a base normalizada.
    expect(localStorage.getItem(STORAGE_KEY)).toBe(antes);
  });

  it("não é o caminho de produção: nem a chave ausente é recriada pela leitura", () => {
    localStorage.removeItem(STORAGE_KEY);

    expect(repository.getColaboradores().length).toBeGreaterThan(0);

    expect(localStorage.getItem(STORAGE_KEY)).toBeNull();
  });

  it("saveColaborador é barreira fail-closed e não grava", () => {
    const antes = localStorage.getItem(STORAGE_KEY);

    expect(() => repository.saveColaborador(colaborador())).toThrow(
      ERRO_ESCRITA_COLABORADOR_SOBERANA
    );
    expect(localStorage.getItem(STORAGE_KEY)).toBe(antes);
    expect(getColaboradorByMatricula(99001)).toBeUndefined();
  });

  it("rejeita gravação duplicada sem substituir o cadastro persistido", () => {
    const existente = colaborador();
    localStorage.setItem(STORAGE_KEY, JSON.stringify([existente]));
    const antes = localStorage.getItem(STORAGE_KEY);

    expect(() =>
      repository.saveColaborador({ ...existente, nome: "Outra Pessoa" })
    ).toThrow(ERRO_ESCRITA_COLABORADOR_SOBERANA);
    expect(localStorage.getItem(STORAGE_KEY)).toBe(antes);
  });

  it("updateColaborador de matrícula inexistente não cria cadastro nem altera histórico", () => {
    const chaveHistorico = "feedback-control-historico-organizacional";
    const historico = '[{"id":"registro-ficticio-preservado"}]';
    localStorage.setItem(chaveHistorico, historico);
    const antes = localStorage.getItem(STORAGE_KEY);

    expect(() => repository.updateColaborador(colaborador())).toThrow(
      ERRO_ESCRITA_COLABORADOR_SOBERANA
    );

    expect(repository.getColaboradorByMatricula(99001)).toBeUndefined();
    expect(localStorage.getItem(STORAGE_KEY)).toBe(antes);
    expect(localStorage.getItem(chaveHistorico)).toBe(historico);
  });

  it("propaga erro de JSON inválido sem substituir dados, como a leitura legada", () => {
    localStorage.setItem(STORAGE_KEY, "json inválido");

    expect(() => repository.getColaboradores()).toThrow(SyntaxError);
    expect(localStorage.getItem(STORAGE_KEY)).toBe("json inválido");
  });
});
