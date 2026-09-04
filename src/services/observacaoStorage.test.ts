import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { Observacao } from "../types/Observacao";
import {
  atualizarObservacao,
  criarObservacao,
  excluirObservacao,
  getObservacoesByColaborador,
} from "./observacaoStorage";

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
const cicloCancelado: CicloAvaliacao = {
  id: "ciclo-cancelado",
  ano: 2026,
  ciclo: 1,
  status: "CANCELADO",
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};
const observacao: Observacao = {
  id: "observacao-preservada",
  colaboradorMatricula: 2,
  tipo: "NEUTRA",
  texto: "Conteúdo preservado",
  comunicado: false,
  ano: cicloCancelado.ano,
  ciclo: cicloCancelado.ciclo,
  autorMatricula: autor.matricula,
  autorNome: autor.nome,
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
  excluida: false,
  historico: [],
};

describe("observações de ciclo cancelado", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      "feedback-control-ciclos",
      JSON.stringify([cicloCancelado])
    );
    localStorage.setItem(
      "feedback-control-observacoes",
      JSON.stringify([observacao])
    );
  });

  it("rejeita criação, edição e exclusão sem modificar observações", () => {
    const operacoes = [
      () =>
        criarObservacao(
          2,
          "POSITIVA",
          "Nova",
          false,
          cicloCancelado.ano,
          cicloCancelado.ciclo,
          autor
        ),
      () =>
        atualizarObservacao(
          observacao.id,
          "POSITIVA",
          "Alterada",
          true,
          cicloCancelado.ano,
          cicloCancelado.ciclo,
          autor
        ),
      () => excluirObservacao(observacao.id, autor),
    ];

    operacoes.forEach((operacao) =>
      expect(operacao).toThrow(
        "Observações só podem ser alteradas enquanto o ciclo estiver ativo."
      )
    );
    expect(
      JSON.parse(localStorage.getItem("feedback-control-observacoes")!)
    ).toEqual([observacao]);
  });
});

describe("mutações de observações vinculadas a ciclos", () => {
  function cicloComStatus(
    status: CicloAvaliacao["status"]
  ): CicloAvaliacao {
    return {
      ...cicloCancelado,
      id: `ciclo-${status.toLowerCase()}`,
      status,
    };
  }

  function preparar(
    status: CicloAvaliacao["status"],
    observacoes: Observacao[] = []
  ) {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      "feedback-control-ciclos",
      JSON.stringify([cicloComStatus(status)])
    );
    localStorage.setItem(
      "feedback-control-observacoes",
      JSON.stringify(observacoes)
    );
  }

  it("permite criação somente em ciclo ativo", () => {
    preparar("ATIVO");

    const criada = criarObservacao(2, "POSITIVA", "Nova", true, 2026, 1, autor);

    expect(criada).toMatchObject({
      colaboradorMatricula: 2,
      ano: 2026,
      ciclo: 1,
      texto: "Nova",
    });
    expect(getObservacoesByColaborador(2)).toHaveLength(1);
  });

  it.each(["PLANEJADO", "ENCERRADO", "CANCELADO"] as const)(
    "rejeita criação em ciclo %s sem persistir dados",
    (status) => {
      preparar(status);

      expect(() =>
        criarObservacao(2, "POSITIVA", "Nova", false, 2026, 1, autor)
      ).toThrow(
        "Observações só podem ser alteradas enquanto o ciclo estiver ativo."
      );
      expect(getObservacoesByColaborador(2)).toEqual([]);
    }
  );

  it("permite edição e exclusão lógica em ciclo ativo", () => {
    preparar("ATIVO", [observacao]);

    atualizarObservacao(
      observacao.id,
      "POSITIVA",
      "Conteúdo atualizado",
      true,
      2026,
      1,
      autor
    );
    let atual = getObservacoesByColaborador(2)[0];
    expect(atual).toMatchObject({
      tipo: "POSITIVA",
      texto: "Conteúdo atualizado",
      comunicado: true,
      dataCriacao: observacao.dataCriacao,
    });
    expect(atual.historico.at(-1)?.acao).toBe("EDICAO");

    excluirObservacao(observacao.id, autor);
    atual = getObservacoesByColaborador(2, true)[0];
    expect(atual.excluida).toBe(true);
    expect(atual.historico.at(-1)?.acao).toBe("EXCLUSAO");
  });

  it.each(["ENCERRADO", "CANCELADO"] as const)(
    "rejeita edição e exclusão em ciclo %s sem modificar dados",
    (status) => {
      preparar(status, [observacao]);
      const antes = localStorage.getItem("feedback-control-observacoes");

      expect(() =>
        atualizarObservacao(
          observacao.id,
          "NEGATIVA",
          "Alterada",
          true,
          2026,
          1,
          autor
        )
      ).toThrow(
        "Observações só podem ser alteradas enquanto o ciclo estiver ativo."
      );
      expect(() => excluirObservacao(observacao.id, autor)).toThrow(
        "Observações só podem ser alteradas enquanto o ciclo estiver ativo."
      );
      expect(localStorage.getItem("feedback-control-observacoes")).toBe(antes);
    }
  );

  it("rejeita mudança do vínculo histórico para outro ciclo", () => {
    preparar("ATIVO", [observacao]);
    const antes = localStorage.getItem("feedback-control-observacoes");

    expect(() =>
      atualizarObservacao(
        observacao.id,
        "POSITIVA",
        "Alterada",
        false,
        2026,
        2,
        autor
      )
    ).toThrow("O ciclo de uma observação existente não pode ser alterado.");
    expect(localStorage.getItem("feedback-control-observacoes")).toBe(antes);
  });

  it("volta a permitir mutação quando o ciclo encerrado retorna a ativo", () => {
    preparar("ENCERRADO", [observacao]);
    expect(() => excluirObservacao(observacao.id, autor)).toThrow();

    localStorage.setItem(
      "feedback-control-ciclos",
      JSON.stringify([cicloComStatus("ATIVO")])
    );
    atualizarObservacao(
      observacao.id,
      "POSITIVA",
      "Editável após reabertura",
      false,
      2026,
      1,
      autor
    );

    expect(getObservacoesByColaborador(2)[0]).toMatchObject({
      id: observacao.id,
      texto: "Editável após reabertura",
      dataCriacao: observacao.dataCriacao,
    });
  });

  it("preserva data de criação e ordenação original após edição", () => {
    const antiga = {
      ...observacao,
      id: "antiga",
      dataCriacao: "2026-01-01T00:00:00.000Z",
      dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
    };
    const nova = {
      ...observacao,
      id: "nova",
      dataCriacao: "2026-02-01T00:00:00.000Z",
      dataUltimaAtualizacao: "2026-02-01T00:00:00.000Z",
    };
    preparar("ATIVO", [antiga, nova]);

    atualizarObservacao(
      antiga.id,
      "NEGATIVA",
      "Observação antiga editada",
      false,
      2026,
      1,
      autor
    );

    const ordenadas = getObservacoesByColaborador(2);
    expect(ordenadas.map((item) => item.id)).toEqual(["nova", "antiga"]);
    expect(ordenadas[1].dataCriacao).toBe(antiga.dataCriacao);
  });
});

describe("ordenação do histórico de observações", () => {
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
    localStorage.setItem("feedback-control-observacoes", JSON.stringify(itens));

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
    localStorage.setItem("feedback-control-observacoes", JSON.stringify(itens));

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
    localStorage.setItem(
      "feedback-control-observacoes",
      JSON.stringify([maisAntiga, maisNova])
    );

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
    localStorage.setItem("feedback-control-observacoes", persistido);

    expect(getObservacoesByColaborador(2).map((item) => item.id)).toEqual([
      "visivel",
    ]);
    expect(
      getObservacoesByColaborador(2, true).map((item) => item.id)
    ).toEqual(["excluida", "visivel"]);
    expect(localStorage.getItem("feedback-control-observacoes")).toBe(
      persistido
    );
  });
});
