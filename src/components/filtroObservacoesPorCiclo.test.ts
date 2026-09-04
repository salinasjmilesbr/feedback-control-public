import { describe, expect, it } from "vitest";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Observacao } from "../types/Observacao";
import {
  contarObservacoesPorTipo,
  filtrarObservacoesPorCiclo,
  getFiltroCicloInicial,
  ordenarCiclosParaFiltro,
} from "./filtroObservacoesPorCiclo";

function ciclo(
  id: string,
  ano: number,
  numero: 1 | 2 | 3,
  status: CicloAvaliacao["status"]
): CicloAvaliacao {
  return {
    id,
    ano,
    ciclo: numero,
    status,
    dataCriacao: "2026-01-01",
    dataUltimaAtualizacao: "2026-01-01",
  };
}

function observacao(
  id: string,
  ano: number,
  numero: 1 | 2 | 3,
  tipo: Observacao["tipo"],
  excluida = false
): Observacao {
  return {
    id,
    colaboradorMatricula: 10,
    tipo,
    texto: id,
    comunicado: false,
    ano,
    ciclo: numero,
    autorMatricula: 1,
    autorNome: "Gestor Fictício",
    dataCriacao: `${ano}-0${numero}-01T00:00:00.000Z`,
    dataUltimaAtualizacao: `${ano}-0${numero}-01T00:00:00.000Z`,
    excluida,
    historico: [],
  };
}

describe("filtro de observações por ciclo", () => {
  const ciclos = [
    ciclo("encerrado-recente", 2027, 3, "ENCERRADO"),
    ciclo("ativo", 2027, 1, "ATIVO"),
    ciclo("encerrado-antigo", 2026, 2, "ENCERRADO"),
  ];

  it("seleciona o ciclo ativo por padrão e o identifica antes dos demais", () => {
    expect(getFiltroCicloInicial(ciclos)).toBe("2027-1");
    expect(ordenarCiclosParaFiltro(ciclos).map((item) => item.id)).toEqual([
      "ativo",
      "encerrado-recente",
      "encerrado-antigo",
    ]);
  });

  it("usa o ciclo cronologicamente mais recente quando não há ativo", () => {
    expect(
      getFiltroCicloInicial(ciclos.filter((item) => item.status !== "ATIVO"))
    ).toBe("2027-3");
    expect(getFiltroCicloInicial([])).toBe("TODOS");
  });

  it("filtra um ciclo histórico e preserva todos no filtro global", () => {
    const observacoes = [
      observacao("positiva-atual", 2027, 1, "POSITIVA"),
      observacao("negativa-historica", 2026, 2, "NEGATIVA"),
      observacao("neutra-historica", 2026, 2, "NEUTRA", true),
    ];

    const historicas = filtrarObservacoesPorCiclo(observacoes, "2026-2");
    expect(historicas.map((item) => item.id)).toEqual([
      "negativa-historica",
      "neutra-historica",
    ]);
    expect(contarObservacoesPorTipo(historicas)).toEqual({
      POSITIVA: 0,
      NEUTRA: 1,
      NEGATIVA: 1,
    });
    expect(filtrarObservacoesPorCiclo(observacoes, "TODOS")).toEqual(
      observacoes
    );
    expect(
      contarObservacoesPorTipo(
        filtrarObservacoesPorCiclo(observacoes, "TODOS")
      )
    ).toEqual({ POSITIVA: 1, NEUTRA: 1, NEGATIVA: 1 });
  });

  it("mantém o filtro de excluídas restrito ao ciclo selecionado", () => {
    const observacoes = [
      observacao("visivel-atual", 2027, 1, "POSITIVA"),
      observacao("excluida-atual", 2027, 1, "NEGATIVA", true),
      observacao("excluida-historica", 2026, 2, "NEUTRA", true),
    ];
    const somenteVisiveis = observacoes.filter((item) => !item.excluida);

    expect(
      filtrarObservacoesPorCiclo(somenteVisiveis, "2027-1").map(
        (item) => item.id
      )
    ).toEqual(["visivel-atual"]);
    expect(
      filtrarObservacoesPorCiclo(observacoes, "2027-1").map((item) => item.id)
    ).toEqual(["visivel-atual", "excluida-atual"]);
  });
});
