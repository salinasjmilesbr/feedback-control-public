import { beforeEach, describe, expect, it, vi } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Observacao } from "../types/Observacao";
import fonteObservacaoStorage from "./observacaoStorage.ts?raw";
import {
  ERRO_ESCRITA_LOCAL_OBSERVACOES,
  atualizarObservacao,
  criarObservacao,
  excluirObservacao,
  getObservacoesByColaborador,
} from "./observacaoStorage";

const CHAVE = "feedback-control-observacoes";
const CHAVE_CICLOS = "feedback-control-ciclos";

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

const ciclo: CicloAvaliacao = {
  id: "ciclo-ficticio",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};

const observacao: Observacao = {
  id: "observacao-preservada",
  colaboradorMatricula: 2,
  tipo: "NEUTRA",
  texto: "Conteúdo preservado",
  comunicado: false,
  ano: ciclo.ano,
  ciclo: ciclo.ciclo,
  autorMatricula: autor.matricula,
  autorNome: autor.nome,
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
  excluida: false,
  historico: [],
};

/**
 * F5-11 P5 (Issue #250) — barreira D13.
 *
 * O acervo local de observações é SOMENTE LEITURA: as três mutações lançam e
 * nenhuma escrita acontece. A autoridade é a porta/repositório soberanos
 * (Edge `observacoes` → RPCs `observacao_*`), sem migração dos dados locais e
 * sem fallback. O gate de ciclo deixou de existir aqui: quem decide ciclo é o
 * servidor (D12), então NENHUM estado de ciclo libera escrita local.
 */
describe("F5-11 P5 — barreira de escrita local de observações (D13)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(CHAVE_CICLOS, JSON.stringify([ciclo]));
    localStorage.setItem(CHAVE, JSON.stringify([observacao]));
  });

  it("as três mutações lançam a barreira e não gravam nada", () => {
    const antes = localStorage.getItem(CHAVE);
    const gravar = vi.spyOn(localStorage, "setItem");

    const operacoes = [
      () =>
        criarObservacao(
          2,
          "POSITIVA",
          "Nova",
          false,
          ciclo.ano,
          ciclo.ciclo,
          autor
        ),
      () =>
        atualizarObservacao(
          observacao.id,
          "POSITIVA",
          "Alterada",
          true,
          ciclo.ano,
          ciclo.ciclo,
          autor
        ),
      () => excluirObservacao(observacao.id, autor),
    ];

    for (const operacao of operacoes) {
      expect(operacao).toThrow(ERRO_ESCRITA_LOCAL_OBSERVACOES);
    }

    expect(localStorage.getItem(CHAVE)).toBe(antes);
    expect(
      gravar.mock.calls.some(([chave]) => chave === CHAVE)
    ).toBe(false);
  });

  it.each(["ATIVO", "PLANEJADO", "ENCERRADO", "CANCELADO"] as const)(
    "nenhum estado de ciclo (%s) libera escrita local — o gate de ciclo é do servidor",
    (status) => {
      localStorage.setItem(
        CHAVE_CICLOS,
        JSON.stringify([{ ...ciclo, status }])
      );
      const antes = localStorage.getItem(CHAVE);

      expect(() =>
        criarObservacao(2, "POSITIVA", "Nova", true, ciclo.ano, ciclo.ciclo, autor)
      ).toThrow(ERRO_ESCRITA_LOCAL_OBSERVACOES);
      expect(() =>
        atualizarObservacao(
          observacao.id,
          "POSITIVA",
          "Alterada",
          false,
          ciclo.ano,
          ciclo.ciclo,
          autor
        )
      ).toThrow(ERRO_ESCRITA_LOCAL_OBSERVACOES);
      expect(() => excluirObservacao(observacao.id, autor)).toThrow(
        ERRO_ESCRITA_LOCAL_OBSERVACOES
      );

      expect(localStorage.getItem(CHAVE)).toBe(antes);
    }
  );

  it("o módulo não contém caminho de escrita nem identidade fabricada no browser", () => {
    // Fonte REAL do módulo (sem comentários removidos): prova estrutural de que
    // a barreira é o ÚNICO destino das mutações.
    expect(fonteObservacaoStorage).not.toContain("localStorage.setItem");
    expect(fonteObservacaoStorage).not.toContain("crypto.randomUUID");
    expect(fonteObservacaoStorage).toContain("barreiraDeEscritaLocal");
    expect(fonteObservacaoStorage).toContain(ERRO_ESCRITA_LOCAL_OBSERVACOES);
  });

  it("as mutações preservam a assinatura pública do acervo legado", () => {
    // Compatibilidade de chamada durante o cutover: as três continuam
    // exportadas como funções (retorno `never` = impossível gravar).
    for (const mutacao of [
      "criarObservacao",
      "atualizarObservacao",
      "excluirObservacao",
    ]) {
      expect(
        new RegExp(`export function ${mutacao}\\([\\s\\S]*?\\): never \\{`).test(
          fonteObservacaoStorage
        ),
        mutacao
      ).toBe(true);
    }
  });

  it("a leitura legada permanece (fora do caminho funcional) e não grava", () => {
    const gravar = vi.spyOn(localStorage, "setItem");

    expect(getObservacoesByColaborador(2).map((item) => item.id)).toEqual([
      observacao.id,
    ]);
    expect(getObservacoesByColaborador(99)).toEqual([]);
    expect(gravar.mock.calls.some(([chave]) => chave === CHAVE)).toBe(false);
  });
});

describe("ordenação do histórico de observações (leitura legada)", () => {
  const criarItem = (
    id: string,
    ano: number,
    ciclo: 1 | 2 | 3,
    tipo: Observacao["tipo"],
    excluida = false
  ): Observacao => ({
    ...observacao,
    id,
    ano,
    ciclo,
    tipo,
    excluida,
    texto: id,
  });

  beforeEach(() => instalarLocalStorageEmMemoria());

  it("ordena globalmente por ano e ciclo em Mais recentes, independentemente do tipo", () => {
    const itens = [
      criarItem("negativa-2026-3", 2026, 3, "NEGATIVA"),
      criarItem("positiva-2027-1", 2027, 1, "POSITIVA"),
      criarItem("neutra-2026-1", 2026, 1, "NEUTRA"),
      criarItem("negativa-2027-2", 2027, 2, "NEGATIVA"),
      criarItem("positiva-2026-2", 2026, 2, "POSITIVA"),
    ];
    localStorage.setItem(CHAVE, JSON.stringify(itens));

    expect(
      getObservacoesByColaborador(2).map((item) => `${item.ano}-${item.ciclo}`)
    ).toEqual(["2027-2", "2027-1", "2026-3", "2026-2", "2026-1"]);
  });

  it("suporta a ordem inversa por ano e ciclo em Mais antigas", () => {
    const itens = [
      criarItem("novo", 2027, 2, "NEUTRA"),
      criarItem("intermediario", 2027, 1, "POSITIVA"),
      criarItem("antigo", 2026, 3, "NEGATIVA"),
    ];
    localStorage.setItem(CHAVE, JSON.stringify(itens));

    expect(
      getObservacoesByColaborador(2, false, "ANTIGAS").map((item) => item.id)
    ).toEqual(["antigo", "intermediario", "novo"]);
  });

  it("ordena observações do mesmo ciclo pela criação sem considerar edições", () => {
    const maisAntiga = {
      ...criarItem("z-antiga", 2027, 2, "POSITIVA"),
      dataCriacao: "2027-03-01T10:00:00.000Z",
      dataUltimaAtualizacao: "2027-12-20T10:00:00.000Z",
    };
    const maisNova = {
      ...criarItem("a-nova", 2027, 2, "NEUTRA"),
      dataCriacao: "2027-04-01T10:00:00.000Z",
      dataUltimaAtualizacao: "2027-04-01T10:00:00.000Z",
    };
    localStorage.setItem(CHAVE, JSON.stringify([maisAntiga, maisNova]));

    expect(
      getObservacoesByColaborador(2, false, "RECENTES").map((item) => item.id)
    ).toEqual(["a-nova", "z-antiga"]);
    expect(
      getObservacoesByColaborador(2, false, "ANTIGAS").map((item) => item.id)
    ).toEqual(["z-antiga", "a-nova"]);
  });

  it("preserva filtros e não modifica os dados persistidos", () => {
    const itens = [
      criarItem("visivel", 2026, 1, "NEUTRA"),
      criarItem("excluida", 2027, 2, "POSITIVA", true),
      {
        ...criarItem("outro-colaborador", 2028, 3, "NEGATIVA"),
        colaboradorMatricula: 99,
      },
    ];
    const persistido = JSON.stringify(itens);
    localStorage.setItem(CHAVE, persistido);

    expect(getObservacoesByColaborador(2).map((item) => item.id)).toEqual([
      "visivel",
    ]);
    expect(
      getObservacoesByColaborador(2, true).map((item) => item.id)
    ).toEqual(["excluida", "visivel"]);
    expect(localStorage.getItem(CHAVE)).toBe(persistido);
  });
});
