import { beforeEach, describe, expect, it } from "vitest";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { MovimentacaoOrganizacional } from "../types/HistoricoOrganizacional";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { obterPermissoesAvaliacao } from "./permissaoAvaliacao";

function pessoa(
  matricula: number,
  funcao: Colaborador["funcao"],
  gestorDiretoMatricula?: number,
  colegiado?: number[]
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
    avaliadoresColegiadoMatriculas: colegiado,
    respondePara: "",
  };
}

const ciclo: CicloAvaliacao = {
  id: "ciclo-2025-1",
  ano: 2025,
  ciclo: 1,
  status: "ENCERRADO",
  dataInicio: "2025-01-01",
  dataFim: "2025-04-30",
  dataCriacao: "2024-12-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2025-05-01T00:00:00.000Z",
};

describe("obterPermissoesAvaliacao", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  it("autoriza o gerente responsável pela cadeia organizacional", () => {
    const gerente = pessoa(1, "GERENTE");
    const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
    const avaliado = pessoa(3, "ANALISTA", coordenador.matricula);

    expect(
      obterPermissoesAvaliacao(gerente, avaliado, [gerente, coordenador, avaliado], ciclo)
    ).toMatchObject({ podeAvaliarComoGerente: true, podeAvaliar: true });
  });

  it("autoriza o coordenador direto do avaliado", () => {
    const gerente = pessoa(1, "GERENTE");
    const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
    const avaliado = pessoa(3, "ANALISTA", coordenador.matricula);

    expect(
      obterPermissoesAvaliacao(coordenador, avaliado, [gerente, coordenador, avaliado], ciclo)
    ).toMatchObject({ podeAvaliarComoCoordenador: true, podeAvaliar: true });
  });

  it("autoriza participante indicado no colegiado", () => {
    const avaliador = pessoa(4, "COORDENADOR");
    const avaliado = pessoa(3, "ANALISTA", undefined, [avaliador.matricula]);

    expect(
      obterPermissoesAvaliacao(avaliador, avaliado, [avaliador, avaliado], ciclo)
    ).toMatchObject({ podeAvaliarComoColegiado: true, podeAvaliar: true });
  });

  it("nega todos os papéis a usuário fora do escopo", () => {
    const gerente = pessoa(1, "GERENTE");
    const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
    const avaliado = pessoa(3, "ANALISTA", coordenador.matricula);
    const externo = pessoa(9, "COORDENADOR");

    expect(
      obterPermissoesAvaliacao(externo, avaliado, [gerente, coordenador, avaliado, externo], ciclo)
    ).toEqual({
      podeAvaliarComoGerente: false,
      podeAvaliarComoCoordenador: false,
      podeAvaliarComoColegiado: false,
      podeAvaliar: false,
      papeisPermitidos: [],
    });
  });

  it("usa a estrutura histórica efetiva do ciclo em vez do vínculo atual", () => {
    const gerente = pessoa(1, "GERENTE");
    const coordenadorAnterior = pessoa(2, "COORDENADOR", gerente.matricula);
    const coordenadorAtual = pessoa(4, "COORDENADOR", gerente.matricula);
    const avaliado = pessoa(3, "ANALISTA", coordenadorAtual.matricula);
    const movimento: MovimentacaoOrganizacional = {
      id: "movimento-1",
      colaboradorMatricula: avaliado.matricula,
      colaboradorNome: avaliado.nome,
      tipo: "ALTERACAO_ESTRUTURA",
      dataVigencia: "2025-06-01",
      dataRegistro: "2025-06-01T12:00:00.000Z",
      escopo: "CICLO_ATUAL_E_POSTERIORES",
      anterior: {
        status: "ATIVO",
        cargo: "ANALISTA",
        area: "Área de teste",
        funcao: "ANALISTA",
        gestorDiretoMatricula: coordenadorAnterior.matricula,
        gestorDiretoNome: coordenadorAnterior.nome,
        avaliadoresColegiadoMatriculas: [],
        avaliadoresColegiadoNomes: [],
      },
      atual: {
        status: "ATIVO",
        cargo: "ANALISTA",
        area: "Área de teste",
        funcao: "ANALISTA",
        gestorDiretoMatricula: coordenadorAtual.matricula,
        gestorDiretoNome: coordenadorAtual.nome,
        avaliadoresColegiadoMatriculas: [],
        avaliadoresColegiadoNomes: [],
      },
    };
    localStorage.setItem(
      "feedback-control-historico-organizacional",
      JSON.stringify([movimento])
    );
    const equipe = [gerente, coordenadorAnterior, coordenadorAtual, avaliado];

    expect(
      obterPermissoesAvaliacao(coordenadorAnterior, avaliado, equipe, ciclo)
        .podeAvaliarComoCoordenador
    ).toBe(true);
    expect(
      obterPermissoesAvaliacao(coordenadorAtual, avaliado, equipe, ciclo)
        .podeAvaliarComoCoordenador
    ).toBe(false);
    expect(
      obterPermissoesAvaliacao(gerente, avaliado, equipe, ciclo)
        .podeAvaliarComoGerente
    ).toBe(true);
  });
});
