/**
 * F5-08 P5 — testes do núcleo de ALOCAÇÃO soberana (ocupação + reporting line).
 *
 * Determinismo: a referência temporal é sempre injetada e a porta é um fake com
 * registro de chamadas — nenhuma rede, nenhum Supabase, nenhum relógio real.
 *
 * Cobre o contrato do P5:
 * - posição futura/encerrada NÃO é vigente (intervalo meio-aberto do P4);
 * - nenhuma intenção é enviada quando a fotografia não contém o item;
 * - ocupação usa `positionId` (UUID) e reporting line usa `positionId` de cada
 *   lado — NUNCA colaborador/cargo/nome/matrícula;
 * - não existe `expectedVersion` nestas operações (contrato F5-07);
 * - troca de posição = encerrar + definir, com desfecho PARCIAL explícito e
 *   nenhum rollback local.
 */

import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  confirmarDefinicaoOcupacao,
  confirmarEncerramentoOcupacao,
  confirmarEncerramentoReportingLine,
  confirmarReportingLine,
  confirmarTrocaDePosicao,
  gestorDiretoDaPosicao,
  ocupacaoVigenteDoColaborador,
  posicaoVigente,
  posicoesGerentesCandidatas,
  posicoesVigentes,
} from "./alocacaoSoberana";
import type { ServiceColaboradores } from "../services/colaboradoresSoberanos/serviceColaboradores";
import { criarColaborador } from "../services/colaboradoresSoberanos/acessoColaboradoresSoberanos";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";

const ORG = "11111111-1111-4111-8111-111111111111";
const COLABORADOR = "22222222-2222-4222-8222-222222222222";
const OUTRO_COLABORADOR = "33333333-3333-4333-8333-333333333333";
const POSICAO = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const POSICAO_GESTOR = "bdbdbdbd-bdbd-4dbd-8dbd-bdbdbdbdbdbd";
const POSICAO_FUTURA = "bfbfbfbf-bfbf-4fbf-8fbf-bfbfbfbfbfbf";
const POSICAO_ENCERRADA = "cececece-cece-4ece-8ece-cececececece";
const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CARGO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const OCUPACAO = "dededede-dede-4ede-8ede-dededededede";
const REPORTING = "cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd";
const OPERACAO_A = "66666666-6666-4666-8666-666666666666";
const OPERACAO_B = "77777777-7777-4777-8777-777777777777";
const VIGENCIA = "2026-03-01";
const MOTIVO = "movimentação aprovada";

const PASSADO = "2026-01-01T00:00:00.000Z";
const FUTURO = "2099-01-01T00:00:00.000Z";
const REFERENCIA = "2026-06-15T12:00:00.000Z";

interface Chamada {
  readonly metodo: string;
  readonly argumentos: unknown;
}

type ServicoFalso = ServiceColaboradores & { readonly chamadas: readonly Chamada[] };

/**
 * Service FAKE que registra TODA chamada (inclusive as sobrescritas no teste), o
 * que permite provar "nenhuma chamada enviada" e "nenhuma chamada extra de
 * rollback".
 */
function servicoFalso(
  comportamentos: Record<string, (entrada: unknown) => Promise<unknown>> = {}
): ServicoFalso {
  const chamadas: Chamada[] = [];
  const respostas: Record<string, (entrada: unknown) => Promise<unknown>> = {
    definirOcupacao: async () => ({ ok: true, dados: POSICAO }),
    encerrarOcupacao: async () => ({ ok: true, dados: null }),
    definirReportingLine: async () => ({ ok: true, dados: REPORTING }),
    encerrarReportingLine: async () => ({ ok: true, dados: null }),
    criar: async () => ({ ok: true, dados: COLABORADOR }),
    ...comportamentos,
  };

  const servico: Record<string, unknown> = {};
  for (const [metodo, responder] of Object.entries(respostas)) {
    servico[metodo] = (entrada: unknown) => {
      chamadas.push({ metodo, argumentos: entrada });
      return responder(entrada);
    };
  }

  return { ...(servico as unknown as ServiceColaboradores), chamadas } as ServicoFalso;
}

function posicao(parcial: Partial<EstruturaSoberana["posicoes"][number]> & {
  posicaoId: string;
}) {
  return {
    unitId: UNIDADE,
    jobRoleId: CARGO,
    seniorityLevelId: null,
    validFrom: PASSADO,
    validTo: null,
    version: 1,
    ...parcial,
  };
}

function estrutura(parcial: Partial<EstruturaSoberana> = {}): EstruturaSoberana {
  return {
    unidades: [{ unitId: UNIDADE, nome: "Unidade Fictícia", validFrom: PASSADO, validTo: null, version: 1 }],
    periodosParent: [],
    posicoes: [
      posicao({ posicaoId: POSICAO }),
      posicao({ posicaoId: POSICAO_GESTOR }),
      posicao({ posicaoId: POSICAO_FUTURA, validFrom: FUTURO }),
      posicao({ posicaoId: POSICAO_ENCERRADA, validFrom: PASSADO, validTo: "2026-03-01T00:00:00.000Z" }),
    ],
    reportingLines: [],
    ocupacoes: [],
    cargos: [
      { jobRoleId: CARGO, code: "FICT", nome: "Cargo Fictício", status: "active", version: 1 },
    ],
    senioridades: [],
    colegiados: [],
    colaboradores: [
      { collaboratorId: COLABORADOR, nome: "Pessoa Fictícia" },
      { collaboratorId: OUTRO_COLABORADOR, nome: "Gestor Fictício" },
    ],
    ...parcial,
  };
}

beforeEach(() => {
  instalarLocalStorageEmMemoria();
});

describe("F5-08 P5 — seleção temporal das posições/ocupações", () => {
  it("posição futura e encerrada não são vigentes; posição com término futuro é", () => {
    const base = estrutura({
      posicoes: [
        posicao({ posicaoId: POSICAO }),
        posicao({ posicaoId: POSICAO_FUTURA, validFrom: FUTURO }),
        posicao({ posicaoId: POSICAO_ENCERRADA, validFrom: PASSADO, validTo: "2026-03-01T00:00:00.000Z" }),
        posicao({ posicaoId: POSICAO_GESTOR, validFrom: PASSADO, validTo: "2026-12-31T00:00:00.000Z" }),
      ],
    });

    const vigentes = posicoesVigentes(base, REFERENCIA).map((item) => item.posicaoId);
    expect(vigentes).toEqual([POSICAO, POSICAO_GESTOR]);

    expect(posicaoVigente(base, POSICAO_FUTURA, REFERENCIA)).toBeNull();
    expect(posicaoVigente(base, POSICAO_ENCERRADA, REFERENCIA)).toBeNull();
    expect(posicaoVigente(base, POSICAO, REFERENCIA)?.posicaoId).toBe(POSICAO);
    expect(posicaoVigente(base, POSICAO_FUTURA, FUTURO)?.posicaoId).toBe(POSICAO_FUTURA);
  });

  it("ocupação futura/encerrada não é a ocupação vigente do colaborador", () => {
    const futura = estrutura({
      ocupacoes: [
        {
          ocupacaoId: OCUPACAO,
          collaboratorId: COLABORADOR,
          posicaoId: POSICAO,
          validFrom: FUTURO,
          validTo: null,
          version: 1,
        },
      ],
    });
    expect(ocupacaoVigenteDoColaborador(futura, COLABORADOR, REFERENCIA)).toBeNull();

    const vigente = estrutura({
      ocupacoes: [
        {
          ocupacaoId: OCUPACAO,
          collaboratorId: COLABORADOR,
          posicaoId: POSICAO,
          validFrom: PASSADO,
          validTo: null,
          version: 1,
        },
      ],
    });
    expect(ocupacaoVigenteDoColaborador(vigente, COLABORADOR, REFERENCIA)?.posicaoId).toBe(
      POSICAO
    );
  });

  it("candidatas a gestor excluem a própria posição e as não vigentes (UX)", () => {
    const candidatas = posicoesGerentesCandidatas(estrutura(), POSICAO, REFERENCIA).map(
      (item) => item.posicaoId
    );
    expect(candidatas).toEqual([POSICAO_GESTOR]);
  });
});

describe("F5-08 P5 — definir ocupação", () => {
  it("envia positionId soberano com vigência, motivo e operationId (sem expectedVersion)", async () => {
    const servico = servicoFalso();

    const desfecho = await confirmarDefinicaoOcupacao(
      {
        estrutura: estrutura(),
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationId: OPERACAO_A,
        organizationId: ORG,
      },
      { operacoes: servico }
    );

    expect(desfecho.tipo).toBe("concluida");
    expect(servico.chamadas).toEqual([
      {
        metodo: "definirOcupacao",
        argumentos: {
          collaboratorId: COLABORADOR,
          operationId: OPERACAO_A,
          positionId: POSICAO,
          vigencia: VIGENCIA,
          motivo: MOTIVO,
          organizationId: ORG,
        },
      },
    ]);
    const payload = servico.chamadas[0]?.argumentos as Record<string, unknown>;
    expect(Object.keys(payload)).not.toContain("expectedVersion");
    expect(Object.keys(payload)).not.toContain("cargo");
  });

  it("posição futura/ausente ⇒ fotografia desatualizada e NENHUMA chamada", async () => {
    const servico = servicoFalso();

    const desfecho = await confirmarDefinicaoOcupacao(
      {
        estrutura: estrutura(),
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO_FUTURA,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationId: OPERACAO_A,
        organizationId: ORG,
      },
      { operacoes: servico }
    );

    expect(desfecho.tipo).toBe("fotografia-desatualizada");
    expect(servico.chamadas).toEqual([]);
  });

  it("motivo e vigência são obrigatórios (forma) antes de qualquer envio", async () => {
    const semMotivo = await confirmarDefinicaoOcupacao(
      {
        estrutura: estrutura(),
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        vigencia: VIGENCIA,
        motivo: "  ",
        operationId: OPERACAO_A,
      },
      { operacoes: servicoFalso() }
    );
    const semVigencia = await confirmarDefinicaoOcupacao(
      {
        estrutura: estrutura(),
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        vigencia: "",
        motivo: MOTIVO,
        operationId: OPERACAO_A,
      },
      { operacoes: servicoFalso() }
    );

    expect(semMotivo).toEqual({ tipo: "sem-motivo" });
    expect(semVigencia).toEqual({ tipo: "sem-vigencia" });
  });
});

describe("F5-08 P5 — encerrar ocupação", () => {
  it("sem ocupação vigente ⇒ fotografia desatualizada e nenhuma chamada", async () => {
    const servico = servicoFalso();

    const desfecho = await confirmarEncerramentoOcupacao(
      {
        estrutura: estrutura(),
        collaboratorId: COLABORADOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationId: OPERACAO_A,
      },
      { operacoes: servico }
    );

    expect(desfecho.tipo).toBe("fotografia-desatualizada");
    expect(servico.chamadas).toEqual([]);
  });

  it("com ocupação vigente envia colaborador + vigência + motivo (sem positionId)", async () => {
    const servico = servicoFalso();
    const comOcupacao = estrutura({
      ocupacoes: [
        {
          ocupacaoId: OCUPACAO,
          collaboratorId: COLABORADOR,
          posicaoId: POSICAO,
          validFrom: PASSADO,
          validTo: null,
          version: 1,
        },
      ],
    });

    const desfecho = await confirmarEncerramentoOcupacao(
      {
        estrutura: comOcupacao,
        collaboratorId: COLABORADOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationId: OPERACAO_A,
        organizationId: ORG,
      },
      { operacoes: servico }
    );

    expect(desfecho.tipo).toBe("concluida");
    expect(servico.chamadas[0]?.metodo).toBe("encerrarOcupacao");
    expect(servico.chamadas[0]?.argumentos).toEqual({
      collaboratorId: COLABORADOR,
      operationId: OPERACAO_A,
      vigencia: VIGENCIA,
      motivo: MOTIVO,
      organizationId: ORG,
    });
  });
});

describe("F5-08 P5 — trocar posição (encerrar + definir, sem atomicidade fingida)", () => {
  const comOcupacao = () =>
    estrutura({
      ocupacoes: [
        {
          ocupacaoId: OCUPACAO,
          collaboratorId: COLABORADOR,
          posicaoId: POSICAO,
          validFrom: PASSADO,
          validTo: null,
          version: 1,
        },
      ],
    });

  it("executa encerrar e depois definir com operationIds DISTINTOS", async () => {
    const servico = servicoFalso();

    const desfecho = await confirmarTrocaDePosicao(
      {
        estrutura: comOcupacao(),
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationIdEncerramento: OPERACAO_A,
        operationIdDefinicao: OPERACAO_B,
        organizationId: ORG,
      },
      { operacoes: servico }
    );

    expect(desfecho).toEqual({ tipo: "concluida" });
    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual([
      "encerrarOcupacao",
      "definirOcupacao",
    ]);
    expect(servico.chamadas[0]?.argumentos).toMatchObject({ operationId: OPERACAO_A });
    expect(servico.chamadas[1]?.argumentos).toMatchObject({
      operationId: OPERACAO_B,
      positionId: POSICAO_GESTOR,
    });
    expect(OPERACAO_A).not.toBe(OPERACAO_B);
  });

  it("falha no encerrar ⇒ nada mudou e a definição NÃO é enviada", async () => {
    const servico = servicoFalso({
      encerrarOcupacao: async () => ({
        ok: false as const,
        codigo: "CONFLICT" as const,
        mensagem: "ocupação mudou",
      }),
    });

    const desfecho = await confirmarTrocaDePosicao(
      {
        estrutura: comOcupacao(),
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationIdEncerramento: OPERACAO_A,
        operationIdDefinicao: OPERACAO_B,
        organizationId: ORG,
      },
      { operacoes: servico }
    );

    expect(desfecho).toEqual({
      tipo: "falhou-encerrar",
      codigo: "CONFLICT",
      mensagem: "ocupação mudou",
    });
    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual(["encerrarOcupacao"]);
  });

  it("falha no definir ⇒ desfecho PARCIAL (sem alocação) e nenhum rollback local", async () => {
    const servico = servicoFalso({
      definirOcupacao: async () => ({
        ok: false as const,
        codigo: "NOT_FOUND" as const,
        mensagem: "posição não encontrada",
      }),
    });

    const desfecho = await confirmarTrocaDePosicao(
      {
        estrutura: comOcupacao(),
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationIdEncerramento: OPERACAO_A,
        operationIdDefinicao: OPERACAO_B,
        organizationId: ORG,
      },
      { operacoes: servico }
    );

    expect(desfecho).toEqual({
      tipo: "parcial",
      codigo: "NOT_FOUND",
      mensagem: "posição não encontrada",
    });
    // Exatamente as duas operações da troca: nenhuma tentativa de "restaurar" a
    // ocupação anterior localmente (nenhuma terceira chamada).
    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual([
      "encerrarOcupacao",
      "definirOcupacao",
    ]);
  });

  it("sem ocupação vigente ou posição inválida, nada é enviado", async () => {
    const semOcupacao = servicoFalso();
    const primeira = await confirmarTrocaDePosicao(
      {
        estrutura: estrutura(),
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationIdEncerramento: OPERACAO_A,
        operationIdDefinicao: OPERACAO_B,
      },
      { operacoes: semOcupacao }
    );
    expect(primeira.tipo).toBe("fotografia-desatualizada");
    expect(semOcupacao.chamadas).toEqual([]);

    const posicaoFutura = servicoFalso();
    const segunda = await confirmarTrocaDePosicao(
      {
        estrutura: comOcupacao(),
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO_FUTURA,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationIdEncerramento: OPERACAO_A,
        operationIdDefinicao: OPERACAO_B,
      },
      { operacoes: posicaoFutura }
    );
    expect(segunda.tipo).toBe("fotografia-desatualizada");
    expect(posicaoFutura.chamadas).toEqual([]);
  });
});

describe("F5-08 P5 — reporting line entre POSIÇÕES", () => {
  it("envia subordinatePositionId e managerPositionId (nunca colaborador/nome/cargo)", async () => {
    const servico = servicoFalso();

    const desfecho = await confirmarReportingLine(
      {
        estrutura: estrutura(),
        subordinatePositionId: POSICAO,
        managerPositionId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationId: OPERACAO_A,
        organizationId: ORG,
      },
      { operacoes: servico }
    );

    expect(desfecho.tipo).toBe("concluida");
    expect(servico.chamadas).toEqual([
      {
        metodo: "definirReportingLine",
        argumentos: {
          subordinatePositionId: POSICAO,
          managerPositionId: POSICAO_GESTOR,
          operationId: OPERACAO_A,
          vigencia: VIGENCIA,
          motivo: MOTIVO,
          organizationId: ORG,
        },
      },
    ]);
    const serializado = JSON.stringify(servico.chamadas[0]?.argumentos);
    expect(serializado).not.toContain(COLABORADOR);
    expect(serializado).not.toContain("Cargo Fictício");
    expect(serializado).not.toContain("expectedVersion");
  });

  it("posição gerente futura ⇒ fotografia desatualizada e nenhuma chamada", async () => {
    const servico = servicoFalso();

    const desfecho = await confirmarReportingLine(
      {
        estrutura: estrutura({
          posicoes: [
            posicao({ posicaoId: POSICAO }),
            posicao({ posicaoId: POSICAO_GESTOR, validFrom: FUTURO }),
          ],
        }),
        subordinatePositionId: POSICAO,
        managerPositionId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationId: OPERACAO_A,
      },
      { operacoes: servico }
    );

    expect(desfecho.tipo).toBe("fotografia-desatualizada");
    expect(servico.chamadas).toEqual([]);
  });

  it("encerrar reporting line exige linha vigente e envia a posição subordinada", async () => {
    const semLinha = servicoFalso();
    const semLinhaDesfecho = await confirmarEncerramentoReportingLine(
      {
        estrutura: estrutura(),
        subordinatePositionId: POSICAO,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationId: OPERACAO_A,
      },
      { operacoes: semLinha }
    );
    expect(semLinhaDesfecho.tipo).toBe("fotografia-desatualizada");
    expect(semLinha.chamadas).toEqual([]);

    const comLinha = servicoFalso();
    const desfecho = await confirmarEncerramentoReportingLine(
      {
        estrutura: estrutura({
          reportingLines: [
            {
              reportingLineId: REPORTING,
              subordinatePositionId: POSICAO,
              managerPositionId: POSICAO_GESTOR,
              motivo: "cadeia anterior",
              validFrom: PASSADO,
              validTo: null,
              version: 1,
            },
          ],
        }),
        subordinatePositionId: POSICAO,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationId: OPERACAO_A,
        organizationId: ORG,
      },
      { operacoes: comLinha }
    );

    expect(desfecho.tipo).toBe("concluida");
    expect(comLinha.chamadas).toEqual([
      {
        metodo: "encerrarReportingLine",
        argumentos: {
          subordinatePositionId: POSICAO,
          operationId: OPERACAO_A,
          vigencia: VIGENCIA,
          motivo: MOTIVO,
          organizationId: ORG,
        },
      },
    ]);
  });

  it("erro do servidor (ciclo/auto-relação) é propagado, nunca antecipado no cliente", async () => {
    const servico = servicoFalso({
      definirReportingLine: async () => ({
        ok: false as const,
        codigo: "CONFLICT" as const,
        mensagem: "reporting line formaria ciclo (recusado pelo banco)",
      }),
    });

    const desfecho = await confirmarReportingLine(
      {
        estrutura: estrutura(),
        subordinatePositionId: POSICAO,
        managerPositionId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationId: OPERACAO_A,
      },
      { operacoes: servico }
    );

    expect(desfecho.tipo).toBe("concluida");
    if (desfecho.tipo !== "concluida") return;
    expect(desfecho.resultado).toEqual({
      ok: false,
      codigo: "CONFLICT",
      mensagem: "reporting line formaria ciclo (recusado pelo banco)",
    });
  });
});

describe("F5-08 P5 — gestor direto derivado da POSIÇÃO", () => {
  const comLinhaEOcupacao = estrutura({
    reportingLines: [
      {
        reportingLineId: REPORTING,
        subordinatePositionId: POSICAO,
        managerPositionId: POSICAO_GESTOR,
        motivo: "cadeia formal",
        validFrom: PASSADO,
        validTo: null,
        version: 1,
      },
    ],
    ocupacoes: [
      {
        ocupacaoId: OCUPACAO,
        collaboratorId: OUTRO_COLABORADOR,
        posicaoId: POSICAO_GESTOR,
        validFrom: PASSADO,
        validTo: null,
        version: 1,
      },
    ],
  });

  it("deriva o gestor do ocupante da posição gerente vigente", () => {
    expect(gestorDiretoDaPosicao(comLinhaEOcupacao, POSICAO, REFERENCIA)).toEqual({
      managerPositionId: POSICAO_GESTOR,
      collaboratorId: OUTRO_COLABORADOR,
    });
  });

  it("posição gerente sem ocupante vigente ⇒ gestor sem pessoa (rótulo é a posição)", () => {
    const semOcupante = estrutura({
      reportingLines: comLinhaEOcupacao.reportingLines,
    });

    expect(gestorDiretoDaPosicao(semOcupante, POSICAO, REFERENCIA)).toEqual({
      managerPositionId: POSICAO_GESTOR,
      collaboratorId: null,
    });
  });

  it("sem reporting line vigente ⇒ posição raiz (nenhum gestor inventado)", () => {
    expect(gestorDiretoDaPosicao(estrutura(), POSICAO, REFERENCIA)).toBeNull();
    expect(
      gestorDiretoDaPosicao(
        estrutura({
          reportingLines: [
            {
              reportingLineId: REPORTING,
              subordinatePositionId: POSICAO,
              managerPositionId: POSICAO_GESTOR,
              motivo: "futura",
              validFrom: FUTURO,
              validTo: null,
              version: 1,
            },
          ],
        }),
        POSICAO,
        REFERENCIA
      )
    ).toBeNull();
  });
});

describe("F5-08 P5 — nenhuma escrita local", () => {
  it("as operações de alocação não tocam localStorage", async () => {
    const armazenamento = instalarLocalStorageEmMemoria();
    const escrever = vi.spyOn(armazenamento, "setItem");

    await confirmarDefinicaoOcupacao(
      {
        estrutura: estrutura(),
        collaboratorId: COLABORADOR,
        posicaoId: POSICAO,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationId: OPERACAO_A,
      },
      { operacoes: servicoFalso() }
    );
    await confirmarReportingLine(
      {
        estrutura: estrutura(),
        subordinatePositionId: POSICAO,
        managerPositionId: POSICAO_GESTOR,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationId: OPERACAO_A,
      },
      { operacoes: servicoFalso() }
    );

    expect(escrever).not.toHaveBeenCalled();
  });
});

describe("F5-08 P5 — criação do colaborador + alocação como operações SEPARADAS", () => {
  /**
   * Fluxo do `NovoColaboradorPage`: cria o colaborador pela porta soberana e, em
   * seguida, tenta a ocupação. Se a ocupação falhar, o colaborador PERMANECE
   * criado, nenhuma estrutura é fabricada e nada é revertido localmente.
   */
  it("ocupação falha depois da criação ⇒ colaborador permanece criado, sem rollback", async () => {
    const servico = servicoFalso({
      criar: async () => ({ ok: true as const, dados: COLABORADOR }),
      definirOcupacao: async () => ({
        ok: false as const,
        codigo: "FORBIDDEN" as const,
        mensagem: "sem permissão para alocar",
      }),
    });

    // 1) criação pela PORTA soberana (operação própria)
    const criacao = await criarColaborador(
      {
        fullName: "Pessoa Fictícia",
        email: "pessoa@example.invalid",
        matricula: "12345",
        operationId: OPERACAO_B,
        organizationId: ORG,
      },
      { operacoes: servico }
    );

    expect(criacao).toEqual({ ok: true, dados: COLABORADOR });
    if (!criacao.ok) return;

    // 2) alocação pelo núcleo do P5, com a MESMA porta injetada
    const desfecho = await confirmarDefinicaoOcupacao(
      {
        estrutura: estrutura(),
        collaboratorId: criacao.dados,
        posicaoId: POSICAO,
        vigencia: VIGENCIA,
        motivo: MOTIVO,
        operationId: OPERACAO_A,
        organizationId: ORG,
      },
      { operacoes: servico }
    );

    expect(desfecho.tipo).toBe("concluida");
    if (desfecho.tipo !== "concluida") return;
    expect(desfecho.resultado).toEqual({
      ok: false,
      codigo: "FORBIDDEN",
      mensagem: "sem permissão para alocar",
    });
    // Nenhuma compensação/rollback: exatamente criar + definir (que falhou).
    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual([
      "criar",
      "definirOcupacao",
    ]);
    // O colaborador criado continua sendo a identidade válida, agora sem alocação.
    expect(criacao.dados).toBe(COLABORADOR);
  });
});
