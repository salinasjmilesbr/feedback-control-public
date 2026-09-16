import { describe, expect, it } from "vitest";
import type { CicloSoberano } from "../application/ports/CycleRepository";
import type { ObservacaoSoberana } from "../application/ports/ObservationRepository";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Observacao } from "../types/Observacao";
import {
  contarObservacoesPorTipo,
  contarObservacoesSoberanasPorTipo,
  filtrarObservacoesPorCiclo,
  filtrarObservacoesSoberanasPorCiclo,
  getChaveCicloObservacoesSoberano,
  getFiltroCicloInicial,
  getFiltroCicloSoberanoInicial,
  ordenarCiclosParaFiltro,
  ordenarCiclosSoberanosParaFiltro,
} from "./filtroObservacoesPorCiclo";

/**
 * F5-11 P5 (Issue #250), L3 — o filtro/KPI do painel soberano usa a IDENTIDADE
 * SOBERANA (`cycleId` UUID). O bloco LEGADO (por `ano`/`ciclo` numéricos) segue
 * coberto para o consumidor de arrasto; nenhuma das duas rotas converte a
 * identidade da outra.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO_ATIVO = "22222222-2222-4222-8222-222222222222";
const CICLO_ANTIGO = "33333333-3333-4333-8333-333333333333";
const ALVO = "44444444-4444-4444-8444-444444444444";

function cicloSoberano(
  id: string,
  ano: number,
  numero: 1 | 2 | 3,
  status: CicloSoberano["status"]
): CicloSoberano {
  return {
    id,
    organizationId: ORG,
    ano,
    numero,
    status,
    dataInicio: null,
    dataFim: null,
    dataAtivacao: null,
    dataEncerramento: null,
    encerradoComPendencias: false,
    quantidadePendencias: 0,
    version: 0,
    criadoEm: "2026-01-01T00:00:00.000Z",
    atualizadoEm: "2026-01-01T00:00:00.000Z",
  };
}

function observacaoSoberana(
  id: string,
  cycleId: string,
  tipo: ObservacaoSoberana["tipo"],
  excluida = false
): ObservacaoSoberana {
  return {
    id,
    organizationId: ORG,
    collaboratorId: ALVO,
    cycleId,
    tipo,
    texto: `observacao ficticia ${id}`,
    comunicado: false,
    comunicadoEm: null,
    excluida,
    motivoExclusao: null,
    autorUserProfileId: "55555555-5555-4555-8555-555555555555",
    autorCollaboratorId: null,
    version: 1,
    criadoEm: "2026-01-01T00:00:00.000Z",
    atualizadoEm: "2026-01-01T00:00:00.000Z",
  };
}

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

describe("filtro soberano de observações por ciclo (identidade = cycleId)", () => {
  const ciclos: CicloSoberano[] = [
    cicloSoberano(CICLO_ANTIGO, 2026, 2, "ENCERRADO"),
    cicloSoberano("66666666-6666-4666-8666-666666666666", 2027, 3, "ENCERRADO"),
    cicloSoberano(CICLO_ATIVO, 2027, 1, "ATIVO"),
  ];

  it("seleciona o ciclo ATIVO por padrão e o identifica antes dos demais", () => {
    expect(getFiltroCicloSoberanoInicial(ciclos)).toEqual({ cycleId: CICLO_ATIVO });
    expect(ordenarCiclosSoberanosParaFiltro(ciclos).map((item) => item.id)).toEqual([
      CICLO_ATIVO,
      "66666666-6666-4666-8666-666666666666",
      CICLO_ANTIGO,
    ]);
    expect(getChaveCicloObservacoesSoberano({ id: CICLO_ATIVO })).toBe(CICLO_ATIVO);
  });

  it("usa o ciclo mais recente quando não há ATIVO e 'TODOS' sem ciclos", () => {
    expect(
      getFiltroCicloSoberanoInicial(ciclos.filter((item) => item.status !== "ATIVO"))
    ).toEqual({ cycleId: "66666666-6666-4666-8666-666666666666" });
    expect(getFiltroCicloSoberanoInicial([])).toBe("TODOS");
  });

  it("filtra pelo UUID do ciclo e preserva todos no filtro global", () => {
    const observacoes = [
      observacaoSoberana("positiva-atual", CICLO_ATIVO, "POSITIVA"),
      observacaoSoberana("negativa-historica", CICLO_ANTIGO, "NEGATIVA"),
      observacaoSoberana("neutra-historica", CICLO_ANTIGO, "NEUTRA", true),
    ];

    const historicas = filtrarObservacoesSoberanasPorCiclo(observacoes, {
      cycleId: CICLO_ANTIGO,
    });
    expect(historicas.map((item) => item.id)).toEqual([
      "negativa-historica",
      "neutra-historica",
    ]);
    expect(contarObservacoesSoberanasPorTipo(historicas)).toEqual({
      POSITIVA: 0,
      NEUTRA: 1,
      NEGATIVA: 1,
    });
    expect(filtrarObservacoesSoberanasPorCiclo(observacoes, "TODOS")).toEqual(
      observacoes
    );
    expect(contarObservacoesSoberanasPorTipo(observacoes)).toEqual({
      POSITIVA: 1,
      NEUTRA: 1,
      NEGATIVA: 1,
    });
  });

  it("o KPI por tipo é compartilhado pelas duas projeções (nunca por ano/ciclo)", () => {
    expect(
      contarObservacoesPorTipo([
        observacaoSoberana("a", CICLO_ATIVO, "POSITIVA"),
        observacaoSoberana("b", CICLO_ATIVO, "POSITIVA"),
      ])
    ).toEqual({ POSITIVA: 2, NEUTRA: 0, NEGATIVA: 0 });
    expect(
      contarObservacoesPorTipo([observacao("l", 2027, 1, "NEGATIVA")])
    ).toEqual({ POSITIVA: 0, NEUTRA: 0, NEGATIVA: 1 });
  });
});

describe("filtro LEGADO de observações por ciclo (ano/ciclo numéricos)", () => {
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
    expect(contarObservacoesPorTipo(observacoes)).toEqual({
      POSITIVA: 1,
      NEUTRA: 1,
      NEGATIVA: 1,
    });
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

  it("filtro SOBERANO aplicado ao acervo legado devolve vazio (sem derivação de identidade)", () => {
    const observacoes = [
      observacao("positiva-atual", 2027, 1, "POSITIVA"),
      observacao("negativa-historica", 2026, 2, "NEGATIVA"),
    ];

    // Não existe ponte `cycleId` → `ano`/`ciclo`: nada casa e nada é inventado.
    expect(
      filtrarObservacoesPorCiclo(observacoes, { cycleId: CICLO_ATIVO })
    ).toEqual([]);
    expect(filtrarObservacoesPorCiclo(observacoes, "TODOS")).toHaveLength(2);
  });
});
