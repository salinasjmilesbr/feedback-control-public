import { beforeEach, describe, expect, it } from "vitest";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import type { MovimentacaoOrganizacional } from "../types/HistoricoOrganizacional";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import {
  ERRO_HISTORICO_ORGANIZACIONAL_SOBERANO,
  getHistoricoOrganizacional,
  getSnapshotOrganizacionalNoCiclo,
  registrarMovimentacaoOrganizacional,
} from "./historicoOrganizacionalStorage";

/**
 * F5-07 — o histórico organizacional é soberano em `collaborator_events`:
 * `registrarMovimentacaoOrganizacional` é BARREIRA (lança e não grava) e a
 * LEITURA legada permanece pura, servindo o acervo já existente.
 */
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
  const transferido: Colaborador = {
    ...colaborador,
    gestorDiretoMatricula: gestorNovo.matricula,
    respondePara: gestorNovo.nome,
  };

  /** Acervo legado já existente (gravado quando o storage ainda era soberano). */
  const movimentoTransferencia: MovimentacaoOrganizacional = {
    id: "movimento-transferencia",
    colaboradorMatricula: colaborador.matricula,
    colaboradorNome: colaborador.nome,
    tipo: "ALTERACAO_ESTRUTURA",
    dataVigencia: "2026-03-15",
    dataRegistro: "2026-03-15T12:00:00.000Z",
    escopo: "CICLO_ATUAL_E_POSTERIORES",
    motivo: "Transferência entre equipes",
    anterior: {
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
    atual: {
      status: "ATIVO",
      cargo: colaborador.cargo,
      area: colaborador.area,
      funcao: colaborador.funcao,
      senioridade: colaborador.senioridade,
      gestorDiretoMatricula: gestorNovo.matricula,
      gestorDiretoNome: gestorNovo.nome,
      avaliadoresColegiadoMatriculas: [],
      avaliadoresColegiadoNomes: [],
    },
    autorMatricula: gerente.matricula,
    autorNome: gerente.nome,
  };

  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      CYCLES_STORAGE_KEY,
      JSON.stringify([cicloAnterior, cicloAtual])
    );
  });

  it("barreira: transferência não é registrada localmente", () => {
    expect(() =>
      registrarMovimentacaoOrganizacional({
        anterior: colaborador,
        atual: transferido,
        colaboradores: equipe,
        dataVigencia: "2026-03-15",
        escopo: "CICLO_ATUAL_E_POSTERIORES",
        motivo: "Transferência entre equipes",
        autorMatricula: gerente.matricula,
        autorNome: gerente.nome,
      })
    ).toThrow(ERRO_HISTORICO_ORGANIZACIONAL_SOBERANO);

    // Fail-closed: nada foi gravado no acervo local.
    expect(localStorage.getItem(HISTORY_STORAGE_KEY)).toBeNull();
    expect(getHistoricoOrganizacional(colaborador.matricula)).toEqual([]);
  });

  it.each([
    ["ATIVO → LICENCA", "ATIVO", "LICENCA"],
    ["LICENCA → ATIVO", "LICENCA", "ATIVO"],
    ["ATIVO → DESLIGADO", "ATIVO", "DESLIGADO"],
  ] as const)(
    "barreira: mudança de status %s não é registrada localmente",
    (_cenario, statusAnterior, statusAtual) => {
      const anterior: Colaborador = { ...colaborador, status: statusAnterior };
      const atual: Colaborador = { ...colaborador, status: statusAtual };

      expect(() =>
        registrarMovimentacaoOrganizacional({
          anterior,
          atual,
          colaboradores: equipe,
          dataVigencia: "2026-04-10",
          escopo: "CICLO_ATUAL_E_POSTERIORES",
          autorMatricula: gerente.matricula,
          autorNome: gerente.nome,
        })
      ).toThrow(ERRO_HISTORICO_ORGANIZACIONAL_SOBERANO);

      expect(localStorage.getItem(HISTORY_STORAGE_KEY)).toBeNull();
      expect(getHistoricoOrganizacional(colaborador.matricula)).toEqual([]);
    }
  );

  it("preserva a estrutura do ciclo anterior a partir do acervo legado", () => {
    localStorage.setItem(
      HISTORY_STORAGE_KEY,
      JSON.stringify([movimentoTransferencia])
    );
    const antes = localStorage.getItem(HISTORY_STORAGE_KEY);

    // A LEITURA reconstrói o snapshot por ciclo sem regravar o storage.
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
    expect(localStorage.getItem(HISTORY_STORAGE_KEY)).toBe(antes);
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
