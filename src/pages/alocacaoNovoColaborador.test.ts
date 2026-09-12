/**
 * F5-08 P5 (correção da auditoria) — testes de COMPORTAMENTO do fluxo
 * criar colaborador + alocar, com foco nos RETRIES parciais.
 *
 * Cenários cobertos (auditoria):
 * 1–4. criar OK → ocupação OK → reporting line FORBIDDEN:
 *      colaborador criado 1×, ocupação criada 1×, estado `sem-gestor` e recarga
 *      da fotografia OBRIGATÓRIA apesar do FORBIDDEN;
 * 5–6. retry em `sem-gestor`: NÃO recria colaborador, NÃO redefine ocupação,
 *      chama SOMENTE a reporting line com NOVO `operationId`;
 * 7.   nenhuma segunda criação de pessoa no fluxo do formulário;
 * 8.   retry em `sem-ocupacao`: chama a ocupação (sem recriar colaborador).
 *
 * Tudo determinístico: porta injetada com registro de chamadas — nenhuma rede,
 * nenhum Supabase, nenhum relógio real.
 */

import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  criarColaboradorComAlocacao,
  deveRecarregarFotografia,
  tentarOcupacao,
  tentarReportingLine,
} from "./alocacaoNovoColaborador";
import type { ServiceColaboradores } from "../services/colaboradoresSoberanos/serviceColaboradores";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";

const ORG = "11111111-1111-4111-8111-111111111111";
const COLABORADOR = "22222222-2222-4222-8222-222222222222";
const POSICAO = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const POSICAO_GESTOR = "bdbdbdbd-bdbd-4dbd-8dbd-bdbdbdbdbdbd";
const POSICAO_ANTIGA = "cececece-cece-4ece-8ece-cececececece";
const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CARGO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const OCUPACAO = "dededede-dede-4ede-8ede-dededededede";
const OPERACAO_CADASTRO = "66666666-6666-4666-8666-666666666666";
const OPERACAO_OCUPACAO = "77777777-7777-4777-8777-777777777777";
const OPERACAO_REPORTING = "88888888-8888-4888-8888-888888888888";
const VIGENCIA = "2026-03-01";
const MOTIVO = "movimentação aprovada";

interface Chamada {
  readonly metodo: string;
  readonly argumentos: Record<string, unknown>;
}

type ServicoFalso = ServiceColaboradores & { readonly chamadas: readonly Chamada[] };

/** Service FAKE que registra TODA chamada (inclusive as sobrescritas). */
function servicoFalso(
  comportamentos: Record<string, (entrada: unknown) => Promise<unknown>> = {}
): ServicoFalso {
  const chamadas: Chamada[] = [];
  const respostas: Record<string, (entrada: unknown) => Promise<unknown>> = {
    criar: async () => ({ ok: true, dados: COLABORADOR }),
    definirOcupacao: async () => ({ ok: true, dados: POSICAO }),
    definirReportingLine: async () => ({ ok: true, dados: "linha-1" }),
    ...comportamentos,
  };

  const servico: Record<string, unknown> = {};
  for (const [metodo, responder] of Object.entries(respostas)) {
    servico[metodo] = (entrada: unknown) => {
      chamadas.push({ metodo, argumentos: entrada as Record<string, unknown> });
      return responder(entrada);
    };
  }

  return { ...(servico as unknown as ServiceColaboradores), chamadas } as ServicoFalso;
}

function posicao(posicaoId: string, validFrom = "2026-01-01T00:00:00.000Z") {
  return {
    posicaoId,
    unitId: UNIDADE,
    jobRoleId: CARGO,
    seniorityLevelId: null,
    validFrom,
    validTo: null,
    version: 1,
  };
}

function estrutura(parcial: Partial<EstruturaSoberana> = {}): EstruturaSoberana {
  return {
    unidades: [
      { unitId: UNIDADE, nome: "Unidade Fictícia", validFrom: "2026-01-01T00:00:00.000Z", validTo: null, version: 1 },
    ],
    periodosParent: [],
    posicoes: [posicao(POSICAO), posicao(POSICAO_GESTOR), posicao(POSICAO_ANTIGA)],
    reportingLines: [],
    ocupacoes: [],
    cargos: [{ jobRoleId: CARGO, code: "FICT", nome: "Cargo Fictício", status: "active", version: 1 }],
    senioridades: [],
    colegiados: [],
    colaboradores: [],
    ...parcial,
  };
}

/** Fotografia APÓS a ocupação gravada (posição em uso = a que foi aceita). */
function comOcupacaoGravada(posicaoId = POSICAO): EstruturaSoberana {
  return estrutura({
    ocupacoes: [
      {
        ocupacaoId: OCUPACAO,
        collaboratorId: COLABORADOR,
        posicaoId,
        validFrom: "2026-01-01T00:00:00.000Z",
        validTo: null,
        version: 1,
      },
    ],
  });
}

const DADOS = {
  fullName: "Pessoa Fictícia",
  email: "pessoa@example.invalid",
  matricula: "12345",
  statusInicial: "active" as const,
};

beforeEach(() => {
  instalarLocalStorageEmMemoria();
});

describe("F5-08 P5 — criar + ocupação OK + reporting FORBIDDEN", () => {
  it("cria 1×, aloca 1×, reporta 1× e devolve estado 'sem-gestor'", async () => {
    const servico = servicoFalso({
      definirReportingLine: async () => ({
        ok: false as const,
        codigo: "FORBIDDEN" as const,
        mensagem: "sem permissão para definir gestor",
      }),
    });

    const desfecho = await criarColaboradorComAlocacao(
      {
        estrutura: estrutura(),
        organizationId: ORG,
        dados: DADOS,
        operationIdCadastro: OPERACAO_CADASTRO,
        alocacao: {
          posicaoId: POSICAO,
          vigencia: VIGENCIA,
          motivo: MOTIVO,
          gestorPosicaoId: POSICAO_GESTOR,
          operationIdOcupacao: OPERACAO_OCUPACAO,
          operationIdReporting: OPERACAO_REPORTING,
        },
      },
      { operacoes: servico }
    );

    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual([
      "criar",
      "definirOcupacao",
      "definirReportingLine",
    ]);
    // Collaborator criado UMA única vez e ocupação criada UMA única vez.
    expect(servico.chamadas.filter((c) => c.metodo === "criar")).toHaveLength(1);
    expect(servico.chamadas.filter((c) => c.metodo === "definirOcupacao")).toHaveLength(1);

    expect(desfecho).toEqual({
      tipo: "criado",
      collaboratorId: COLABORADOR,
      alocacao: {
        estado: "sem-gestor",
        codigo: "FORBIDDEN",
        mensagem: "sem permissão para definir gestor",
      },
    });
  });

  it("a fotografia é recarregada MESMO com FORBIDDEN (mutação da ocupação ocorreu)", () => {
    expect(
      deveRecarregarFotografia({
        estado: "sem-gestor",
        codigo: "FORBIDDEN",
        mensagem: "sem permissão",
      })
    ).toBe(true);
    expect(
      deveRecarregarFotografia({
        estado: "sem-gestor",
        codigo: "INTERNAL",
        mensagem: "falha inesperada",
      })
    ).toBe(true);
    expect(
      deveRecarregarFotografia({
        estado: "sem-gestor",
        codigo: "INVALID_INPUT",
        mensagem: "vigência inválida",
      })
    ).toBe(true);

    // Em `sem-ocupacao` não houve mutação: recarrega só com leitura desatualizada.
    expect(
      deveRecarregarFotografia({
        estado: "sem-ocupacao",
        codigo: "FORBIDDEN",
        mensagem: "sem permissão",
      })
    ).toBe(false);
    expect(
      deveRecarregarFotografia({
        estado: "sem-ocupacao",
        codigo: "CONFLICT",
        mensagem: "posição mudou",
      })
    ).toBe(true);
  });
});

describe("F5-08 P5 — RETRY em 'sem-gestor' tenta SOMENTE a reporting line", () => {
  it("não recria colaborador, não redefine ocupação e usa NOVO operationId", async () => {
    const servico = servicoFalso();
    const fotografia = comOcupacaoGravada();
    const novoOperationId = "99999999-9999-4999-8999-999999999999";

    const desfecho = await tentarReportingLine(
      {
        estrutura: fotografia,
        organizationId: ORG,
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        gestorPosicaoId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationIdReporting: novoOperationId,
      },
      { operacoes: servico }
    );

    expect(desfecho).toEqual({ estado: "completa" });
    // SOMENTE a reporting line: nada de criar/definirOcupacao no retry.
    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual([
      "definirReportingLine",
    ]);
    expect(servico.chamadas[0]?.argumentos).toEqual({
      subordinatePositionId: POSICAO,
      managerPositionId: POSICAO_GESTOR,
      operationId: novoOperationId,
      vigencia: VIGENCIA,
      motivo: MOTIVO,
      organizationId: ORG,
    });
    // Novo operationId (diferente dos usados na primeira tentativa).
    expect(servico.chamadas[0]?.argumentos.operationId).not.toBe(OPERACAO_REPORTING);
    expect(servico.chamadas[0]?.argumentos.operationId).not.toBe(OPERACAO_OCUPACAO);
  });

  it("usa a posição da OCUPAÇÃO VIGENTE da fotografia corrente como subordinada", async () => {
    const servico = servicoFalso();

    await tentarReportingLine(
      {
        estrutura: comOcupacaoGravada(POSICAO_ANTIGA),
        organizationId: ORG,
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        gestorPosicaoId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationIdReporting: OPERACAO_REPORTING,
      },
      { operacoes: servico }
    );

    // A fotografia (servidor) prevalece sobre a intenção local.
    expect(servico.chamadas[0]?.argumentos.subordinatePositionId).toBe(POSICAO_ANTIGA);
    expect(servico.chamadas[0]?.argumentos.managerPositionId).toBe(POSICAO_GESTOR);
  });

  it("sem gestor escolhido, o retry recusa antes de enviar (INVALID_INPUT)", async () => {
    const servico = servicoFalso();

    const desfecho = await tentarReportingLine(
      {
        estrutura: comOcupacaoGravada(),
        organizationId: ORG,
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        gestorPosicaoId: null,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationIdReporting: OPERACAO_REPORTING,
      },
      { operacoes: servico }
    );

    expect(desfecho.estado).toBe("sem-gestor");
    expect(servico.chamadas).toEqual([]);
  });

  it("se a posição gerente não está mais vigente, nada é enviado (fotografia desatualizada)", async () => {
    const servico = servicoFalso();
    const gestorFuturo = estrutura({
      posicoes: [posicao(POSICAO), posicao(POSICAO_GESTOR, "2099-01-01T00:00:00.000Z")],
      ocupacoes: comOcupacaoGravada().ocupacoes,
    });

    const desfecho = await tentarReportingLine(
      {
        estrutura: gestorFuturo,
        organizationId: ORG,
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        gestorPosicaoId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationIdReporting: OPERACAO_REPORTING,
      },
      { operacoes: servico }
    );

    expect(desfecho).toMatchObject({ estado: "sem-gestor", codigo: "CONFLICT" });
    expect(servico.chamadas).toEqual([]);
  });
});

describe("F5-08 P5 — RETRY em 'sem-ocupacao' tenta a ocupação (sem recriar pessoa)", () => {
  it("chama a ocupação e, com gestor escolhido, a reporting line — nunca 'criar'", async () => {
    const servico = servicoFalso();

    const desfecho = await tentarOcupacao(
      {
        estrutura: estrutura(),
        organizationId: ORG,
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        gestorPosicaoId: POSICAO_GESTOR,
        operationIdOcupacao: OPERACAO_OCUPACAO,
        operationIdReporting: OPERACAO_REPORTING,
      },
      { operacoes: servico }
    );

    expect(desfecho).toEqual({ estado: "completa" });
    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual([
      "definirOcupacao",
      "definirReportingLine",
    ]);
    expect(servico.chamadas.some((chamada) => chamada.metodo === "criar")).toBe(false);
    expect(servico.chamadas[0]?.argumentos).toMatchObject({
      collaboratorId: COLABORADOR,
      positionId: POSICAO,
      operationId: OPERACAO_OCUPACAO,
    });
  });

  it("se a ocupação falhar de novo, NÃO tenta a reporting line", async () => {
    const servico = servicoFalso({
      definirOcupacao: async () => ({
        ok: false as const,
        codigo: "FORBIDDEN" as const,
        mensagem: "sem permissão para alocar",
      }),
    });

    const desfecho = await tentarOcupacao(
      {
        estrutura: estrutura(),
        organizationId: ORG,
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        gestorPosicaoId: POSICAO_GESTOR,
        operationIdOcupacao: OPERACAO_OCUPACAO,
        operationIdReporting: OPERACAO_REPORTING,
      },
      { operacoes: servico }
    );

    expect(desfecho).toEqual({
      estado: "sem-ocupacao",
      codigo: "FORBIDDEN",
      mensagem: "sem permissão para alocar",
    });
    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual(["definirOcupacao"]);
  });

  it("sem gestor escolhido, a ocupação conclui a alocação sem reporting line", async () => {
    const servico = servicoFalso();

    const desfecho = await tentarOcupacao(
      {
        estrutura: estrutura(),
        organizationId: ORG,
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        gestorPosicaoId: null,
        operationIdOcupacao: OPERACAO_OCUPACAO,
        operationIdReporting: OPERACAO_REPORTING,
      },
      { operacoes: servico }
    );

    expect(desfecho).toEqual({ estado: "completa" });
    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual(["definirOcupacao"]);
  });
});

describe("F5-08 P5 — nenhuma segunda criação de pessoa", () => {
  it("erro de cadastro não cria ocupação e não repete a criação", async () => {
    const servico = servicoFalso({
      criar: async () => ({
        ok: false as const,
        codigo: "CONFLICT" as const,
        mensagem: "matrícula já utilizada",
      }),
    });

    const desfecho = await criarColaboradorComAlocacao(
      {
        estrutura: estrutura(),
        organizationId: ORG,
        dados: DADOS,
        operationIdCadastro: OPERACAO_CADASTRO,
        alocacao: {
          posicaoId: POSICAO,
          vigencia: VIGENCIA,
          motivo: MOTIVO,
          gestorPosicaoId: null,
          operationIdOcupacao: OPERACAO_OCUPACAO,
          operationIdReporting: OPERACAO_REPORTING,
        },
      },
      { operacoes: servico }
    );

    expect(desfecho).toEqual({
      tipo: "erro-cadastro",
      codigo: "CONFLICT",
      mensagem: "matrícula já utilizada",
    });
    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual(["criar"]);
  });

  it("sem alocação pedida, cria uma única vez e informa 'nenhuma' alocação", async () => {
    const servico = servicoFalso();

    const desfecho = await criarColaboradorComAlocacao(
      {
        estrutura: estrutura(),
        organizationId: ORG,
        dados: DADOS,
        operationIdCadastro: OPERACAO_CADASTRO,
        alocacao: null,
      },
      { operacoes: servico }
    );

    expect(desfecho).toEqual({
      tipo: "criado",
      collaboratorId: COLABORADOR,
      alocacao: { estado: "nenhuma" },
    });
    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual(["criar"]);
  });

  it("o fluxo de retry nunca chama a criação da pessoa (nem a ocupação duas vezes)", async () => {
    const servico = servicoFalso();

    await tentarReportingLine(
      {
        estrutura: comOcupacaoGravada(),
        organizationId: ORG,
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        gestorPosicaoId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationIdReporting: OPERACAO_REPORTING,
      },
      { operacoes: servico }
    );
    await tentarOcupacao(
      {
        estrutura: estrutura(),
        organizationId: ORG,
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        gestorPosicaoId: null,
        operationIdOcupacao: OPERACAO_OCUPACAO,
        operationIdReporting: OPERACAO_REPORTING,
      },
      { operacoes: servico }
    );

    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual([
      "definirReportingLine",
      "definirOcupacao",
    ]);
    expect(servico.chamadas.filter((c) => c.metodo === "criar")).toHaveLength(0);
    expect(servico.chamadas.filter((c) => c.metodo === "definirOcupacao")).toHaveLength(1);
  });
});

describe("F5-08 P5 — nenhuma escrita local no fluxo de retry", () => {
  it("os retries não tocam localStorage", async () => {
    const armazenamento = instalarLocalStorageEmMemoria();
    const escrever = vi.spyOn(armazenamento, "setItem");

    await tentarReportingLine(
      {
        estrutura: comOcupacaoGravada(),
        organizationId: ORG,
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        gestorPosicaoId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationIdReporting: OPERACAO_REPORTING,
      },
      { operacoes: servicoFalso() }
    );

    expect(escrever).not.toHaveBeenCalled();
  });
});
