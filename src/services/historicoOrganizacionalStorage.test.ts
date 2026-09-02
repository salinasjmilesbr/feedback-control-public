import { beforeEach, describe, expect, it } from "vitest";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { MovimentacaoOrganizacional } from "../types/HistoricoOrganizacional";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import {
  getHistoricoOrganizacional,
  getSnapshotOrganizacionalNoCiclo,
  registrarMovimentacaoOrganizacional,
} from "./historicoOrganizacionalStorage";

const HISTORY_STORAGE_KEY = "feedback-control-historico-organizacional";
const CYCLES_STORAGE_KEY = "feedback-control-ciclos";

function pessoa(
  matricula: number,
  funcao: Colaborador["funcao"],
  gestorDiretoMatricula?: number
): Colaborador {
  return {
    matricula,
    status: "ATIVO",
    nome: `Pessoa ${matricula}`,
    email: `pessoa.${matricula}@example.com`,
    cargo: funcao === "GERENTE" ? "Gerente" : "Analista",
    area: "Área de Testes",
    funcao,
    senioridade: funcao === "ANALISTA" ? "PLENO" : undefined,
    gestorDiretoMatricula,
    respondePara: "",
  };
}

const cicloAnterior: CicloAvaliacao = {
  id: "ciclo-anterior",
  ano: 2025,
  ciclo: 2,
  status: "ENCERRADO",
  dataInicio: "2025-07-01",
  dataFim: "2025-12-31",
  dataCriacao: "2025-06-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2025-12-31T00:00:00.000Z",
  dataEncerramento: "2025-12-31T00:00:00.000Z",
};

const cicloAtual: CicloAvaliacao = {
  id: "ciclo-atual",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataInicio: "2026-01-01",
  dataFim: "2026-12-31",
  dataCriacao: "2025-12-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};

describe("historicoOrganizacionalStorage", () => {
  const gerente = pessoa(1, "GERENTE");
  const gestorAnterior = pessoa(2, "COORDENADOR", gerente.matricula);
  const gestorNovo = pessoa(3, "COORDENADOR", gerente.matricula);
  const colaborador = pessoa(4, "ANALISTA", gestorAnterior.matricula);
  const equipe = [gerente, gestorAnterior, gestorNovo, colaborador];

  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      CYCLES_STORAGE_KEY,
      JSON.stringify([cicloAnterior, cicloAtual])
    );
  });

  it("registra origem, destino, autor, vigência e motivo na transferência", () => {
    const transferido: Colaborador = {
      ...colaborador,
      gestorDiretoMatricula: gestorNovo.matricula,
      respondePara: gestorNovo.nome,
    };

    const movimento = registrarMovimentacaoOrganizacional({
      anterior: colaborador,
      atual: transferido,
      colaboradores: equipe,
      dataVigencia: "2026-03-15",
      escopo: "CICLO_ATUAL_E_POSTERIORES",
      motivo: "Transferência entre equipes",
      autorMatricula: gerente.matricula,
      autorNome: gerente.nome,
    });

    expect(movimento).toMatchObject({
      tipo: "ALTERACAO_ESTRUTURA",
      dataVigencia: "2026-03-15",
      motivo: "Transferência entre equipes",
      autorMatricula: gerente.matricula,
      autorNome: gerente.nome,
      anterior: {
        gestorDiretoMatricula: gestorAnterior.matricula,
        gestorDiretoNome: gestorAnterior.nome,
      },
      atual: {
        gestorDiretoMatricula: gestorNovo.matricula,
        gestorDiretoNome: gestorNovo.nome,
      },
    });
  });

  it.each([
    ["ATIVO → LICENCA", "ATIVO", "LICENCA", "LICENCA"],
    ["LICENCA → ATIVO", "LICENCA", "ATIVO", "RETORNO_LICENCA"],
    ["ATIVO → DESLIGADO", "ATIVO", "DESLIGADO", "DESLIGAMENTO"],
  ] as const)(
    "registra a mudança de status %s com estado anterior e novo",
    (_cenario, statusAnterior, statusAtual, tipoEsperado) => {
      const anterior: Colaborador = { ...colaborador, status: statusAnterior };
      const atual: Colaborador = { ...colaborador, status: statusAtual };

      const movimento = registrarMovimentacaoOrganizacional({
        anterior,
        atual,
        colaboradores: equipe,
        dataVigencia: "2026-04-10",
        escopo: "CICLO_ATUAL_E_POSTERIORES",
        autorMatricula: gerente.matricula,
        autorNome: gerente.nome,
      });

      expect(movimento.tipo).toBe(tipoEsperado);
      expect(movimento.anterior?.status).toBe(statusAnterior);
      expect(movimento.atual.status).toBe(statusAtual);
    }
  );

  it("preserva a estrutura do ciclo anterior após movimentação atual", () => {
    const transferido: Colaborador = {
      ...colaborador,
      gestorDiretoMatricula: gestorNovo.matricula,
      respondePara: gestorNovo.nome,
    };

    registrarMovimentacaoOrganizacional({
      anterior: colaborador,
      atual: transferido,
      colaboradores: equipe,
      dataVigencia: "2026-03-15",
      escopo: "CICLO_ATUAL_E_POSTERIORES",
      autorMatricula: gerente.matricula,
      autorNome: gerente.nome,
    });

    expect(
      getSnapshotOrganizacionalNoCiclo(
        transferido,
        cicloAnterior,
        cicloAnterior.dataFim
      ).gestorDiretoMatricula
    ).toBe(gestorAnterior.matricula);
    expect(
      getSnapshotOrganizacionalNoCiclo(
        transferido,
        cicloAtual,
        "2026-03-15"
      ).gestorDiretoMatricula
    ).toBe(gestorNovo.matricula);
  });

  it("mantém compatibilidade com movimentação antiga sem autoria", () => {
    const movimentoAntigo: MovimentacaoOrganizacional = {
      id: "movimento-antigo",
      colaboradorMatricula: colaborador.matricula,
      colaboradorNome: colaborador.nome,
      tipo: "ALTERACAO_ESTRUTURA",
      dataVigencia: "2025-01-01",
      dataRegistro: "2025-01-01T00:00:00.000Z",
      escopo: "CICLO_ATUAL_E_POSTERIORES",
      atual: {
        status: "ATIVO",
        cargo: colaborador.cargo,
        area: colaborador.area,
        funcao: colaborador.funcao,
        senioridade: colaborador.senioridade,
        gestorDiretoMatricula: gestorAnterior.matricula,
        gestorDiretoNome: gestorAnterior.nome,
        avaliadoresColegiadoMatriculas: [],
        avaliadoresColegiadoNomes: [],
      },
    };
    localStorage.setItem(
      HISTORY_STORAGE_KEY,
      JSON.stringify([movimentoAntigo])
    );

    const historico = getHistoricoOrganizacional(colaborador.matricula);

    expect(historico).toEqual([movimentoAntigo]);
    expect(historico[0].autorNome).toBeUndefined();
  });
});
