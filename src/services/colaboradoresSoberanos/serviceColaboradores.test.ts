import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { instalarLocalStorageEmMemoria } from "../../test/localStorageMock";
import {
  criarRepositorioColaboradoresProducao,
  criarServiceColaboradores,
  mensagemColaboradores,
  type ServiceColaboradores,
} from "./serviceColaboradores";
import type {
  ColaboradorSoberano,
  EventoColaborador,
  RepositorioColaboradores,
  ResultadoRepositorioColaboradores,
} from "../../infrastructure/supabase/colaboradores/repositorioColaboradores";
import type { CodigoPublico } from "../../infrastructure/supabase/colaboradores/contrato";

/**
 * F5-07 — casos de uso do caminho soberano de colaboradores (§3/§9).
 *
 * O repositório é SEMPRE injetado (nenhuma rede, nenhum Supabase real). O que
 * este teste prova:
 * - a organização ativa é INTENÇÃO de UX (resolvida aqui, revalidada na Edge);
 * - sucesso normaliza a projeção (`ColaboradorSoberano`) sem vazar payload cru;
 * - `NOT_FOUND`/`FORBIDDEN`/`CONFLICT`/... viram `{ ok:false, codigo }` — nunca
 *   exceção, nunca mensagem interna do banco;
 * - ausência de organização ativa ou de configuração de ambiente é FAIL-CLOSED
 *   (`FORBIDDEN`/`INTERNAL`) e NUNCA cai para `localStorage`.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const OUTRA_ORG = "99999999-9999-4999-8999-999999999999";
const COLABORADOR = "22222222-2222-4222-8222-222222222222";
const POSICAO = "33333333-3333-4333-8333-333333333333";
const OPERACAO_ID = "66666666-6666-4666-8666-666666666666";
const RESPONSABILIDADE = "88888888-8888-4888-8888-888888888888";
const CICLO = "55555555-5555-4555-8555-555555555555";
const VIGENCIA = "2026-03-01T00:00:00.000Z";
// F5-08 P4 — identidades fictícias das entidades estruturais/catalogais.
const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const PERIODO = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const COLEGIADO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const CARGO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const SENIORIDADE = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";

function colaboradorSoberano(parcial: Partial<ColaboradorSoberano> = {}): ColaboradorSoberano {
  return {
    collaboratorId: COLABORADOR,
    matricula: "1234",
    fullName: "Maria Silva",
    email: "maria@example.invalid",
    status: "active",
    admissionDate: "2024-02-01",
    unitId: POSICAO,
    unitName: "Unidade Fictícia",
    jobRoleCode: "ANALISTA",
    jobRoleName: "Analista",
    seniorityName: "Pleno",
    managerCollaboratorId: null,
    managerFullName: null,
    version: 3,
    ...parcial,
  };
}

function eventoColaborador(): EventoColaborador {
  return {
    eventId: RESPONSABILIDADE,
    eventType: "ADMISSAO",
    effectiveDate: VIGENCIA,
    reason: "admissão",
    cycleScope: "CICLO_ATUAL_E_POSTERIORES",
    referenceCycleId: null,
    actorUserProfileId: ORG,
    actorFullName: "Ator Fictício",
    beforeValue: null,
    afterValue: null,
    createdAt: VIGENCIA,
  };
}

interface MetodoChamado {
  readonly metodo: string;
  readonly argumentos: unknown;
}

type RepositorioFalso = RepositorioColaboradores & {
  readonly chamadas: readonly MetodoChamado[];
};

/** Repositório FAKE com registro de chamadas (nenhum comportamento é real). */
function repositorioFalso(
  comportamentos: Partial<RepositorioColaboradores> = {}
): RepositorioFalso {
  const chamadas: MetodoChamado[] = [];
  const registrar = <T>(
    metodo: string,
    valor: unknown,
    resposta: ResultadoRepositorioColaboradores<T>
  ) => {
    chamadas.push({ metodo, argumentos: valor });
    return Promise.resolve(resposta);
  };

  const padrao: RepositorioColaboradores = {
    listar: (entrada) => registrar("listar", entrada, { ok: true, data: [colaboradorSoberano()] }),
    obter: (entrada) =>
      registrar("obter", entrada, {
        ok: true,
        data: {
          colaborador: colaboradorSoberano(),
          resultadoCru: { collaborator_id: COLABORADOR, coluna_interna: "não deve vazar" },
        },
      }),
    criar: (entrada) => registrar("criar", entrada, { ok: true, data: COLABORADOR }),
    editar: (entrada) => registrar("editar", entrada, { ok: true, data: 4 }),
    definirIdentificador: (entrada) => registrar("definirIdentificador", entrada, { ok: true, data: 5 }),
    alterarStatus: (entrada) => registrar("alterarStatus", entrada, { ok: true, data: 4 }),
    definirOcupacao: (entrada) => registrar("definirOcupacao", entrada, { ok: true, data: POSICAO }),
    encerrarOcupacao: (entrada) => registrar("encerrarOcupacao", entrada, { ok: true, data: null }),
    definirReportingLine: (entrada) =>
      registrar("definirReportingLine", entrada, { ok: true, data: POSICAO }),
    encerrarReportingLine: (entrada) =>
      registrar("encerrarReportingLine", entrada, { ok: true, data: null }),
    definirResponsabilidade: (entrada) =>
      registrar("definirResponsabilidade", entrada, { ok: true, data: RESPONSABILIDADE }),
    encerrarResponsabilidade: (entrada) =>
      registrar("encerrarResponsabilidade", entrada, { ok: true, data: null }),
    registrarSucessao: (entrada) => registrar("registrarSucessao", entrada, { ok: true, data: null }),
    obterHistorico: (entrada) =>
      registrar("obterHistorico", entrada, { ok: true, data: [eventoColaborador()] }),
    bootstrapCatalogo: (entrada) => registrar("bootstrapCatalogo", entrada, { ok: true, data: null }),
    // F5-08 P4 — operações estruturais/catalogais do P3 (cliente).
    criarUnidade: (entrada) => registrar("criarUnidade", entrada, { ok: true, data: UNIDADE }),
    renomearUnidade: (entrada) => registrar("renomearUnidade", entrada, { ok: true, data: 4 }),
    encerrarUnidade: (entrada) => registrar("encerrarUnidade", entrada, { ok: true, data: 5 }),
    definirParentUnidade: (entrada) =>
      registrar("definirParentUnidade", entrada, { ok: true, data: PERIODO }),
    encerrarParentUnidade: (entrada) =>
      registrar("encerrarParentUnidade", entrada, { ok: true, data: PERIODO }),
    criarPosicao: (entrada) => registrar("criarPosicao", entrada, { ok: true, data: POSICAO }),
    encerrarPosicao: (entrada) => registrar("encerrarPosicao", entrada, { ok: true, data: 6 }),
    definirColegiado: (entrada) =>
      registrar("definirColegiado", entrada, { ok: true, data: COLEGIADO }),
    encerrarColegiado: (entrada) =>
      registrar("encerrarColegiado", entrada, { ok: true, data: COLEGIADO }),
    criarCargo: (entrada) => registrar("criarCargo", entrada, { ok: true, data: CARGO }),
    renomearCargo: (entrada) => registrar("renomearCargo", entrada, { ok: true, data: 2 }),
    alterarStatusCargo: (entrada) => registrar("alterarStatusCargo", entrada, { ok: true, data: 3 }),
    criarSenioridade: (entrada) => registrar("criarSenioridade", entrada, { ok: true, data: SENIORIDADE }),
    renomearSenioridade: (entrada) =>
      registrar("renomearSenioridade", entrada, { ok: true, data: 2 }),
    alterarStatusSenioridade: (entrada) =>
      registrar("alterarStatusSenioridade", entrada, { ok: true, data: 3 }),
  };

  return { ...padrao, ...comportamentos, chamadas };
}

function servicoCom(
  repositorio: RepositorioColaboradores,
  organizacaoAtivaId: () => string | null | undefined = () => ORG
): ServiceColaboradores {
  return criarServiceColaboradores({ repositorio, organizacaoAtivaId });
}

function falhaRepositorio(
  code: CodigoPublico,
  message = "detalhe interno do banco"
): Partial<RepositorioColaboradores> {
  const erro = { ok: false as const, error: { code, message } };
  return {
    listar: () => Promise.resolve(erro),
    obter: () => Promise.resolve(erro),
    criar: () => Promise.resolve(erro),
    editar: () => Promise.resolve(erro),
    definirIdentificador: () => Promise.resolve(erro),
    alterarStatus: () => Promise.resolve(erro),
    definirOcupacao: () => Promise.resolve(erro),
    encerrarOcupacao: () => Promise.resolve(erro),
    definirReportingLine: () => Promise.resolve(erro),
    encerrarReportingLine: () => Promise.resolve(erro),
    definirResponsabilidade: () => Promise.resolve(erro),
    encerrarResponsabilidade: () => Promise.resolve(erro),
    registrarSucessao: () => Promise.resolve(erro),
    obterHistorico: () => Promise.resolve(erro),
    bootstrapCatalogo: () => Promise.resolve(erro),
    criarUnidade: () => Promise.resolve(erro),
    renomearUnidade: () => Promise.resolve(erro),
    encerrarUnidade: () => Promise.resolve(erro),
    definirParentUnidade: () => Promise.resolve(erro),
    encerrarParentUnidade: () => Promise.resolve(erro),
    criarPosicao: () => Promise.resolve(erro),
    encerrarPosicao: () => Promise.resolve(erro),
    definirColegiado: () => Promise.resolve(erro),
    encerrarColegiado: () => Promise.resolve(erro),
    criarCargo: () => Promise.resolve(erro),
    renomearCargo: () => Promise.resolve(erro),
    alterarStatusCargo: () => Promise.resolve(erro),
    criarSenioridade: () => Promise.resolve(erro),
    renomearSenioridade: () => Promise.resolve(erro),
    alterarStatusSenioridade: () => Promise.resolve(erro),
  } as Partial<RepositorioColaboradores>;
}

let armazenamento: Storage;

beforeEach(() => {
  armazenamento = instalarLocalStorageEmMemoria();
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.resetModules();
});

const RESOLVEDORES_SEM_ORGANIZACAO: ReadonlyArray<
  readonly [string, () => string | null | undefined]
> = [
  ["ausente", () => undefined],
  ["nula", () => null],
  ["vazia", () => ""],
];

describe("F5-07 service — organização ativa como INTENÇÃO de UX", () => {
  it("resolve a organização ativa e a envia ao repositório (sem autoridade local)", async () => {
    const repositorio = repositorioFalso();
    const servico = servicoCom(repositorio);

    const resultado = await servico.listar({});

    expect(resultado).toEqual({ ok: true, dados: [colaboradorSoberano()] });
    expect(repositorio.chamadas).toEqual([{ metodo: "listar", argumentos: { organizationId: ORG } }]);
  });

  it("a organização informada pela TELA prevalece como intenção", async () => {
    const repositorio = repositorioFalso();
    const servico = servicoCom(repositorio);

    await servico.listar({ organizationId: OUTRA_ORG, status: "leave", busca: "silva" });

    expect(repositorio.chamadas[0]?.argumentos).toEqual({
      organizationId: OUTRA_ORG,
      status: "leave",
      busca: "silva",
    });
  });

  it.each(RESOLVEDORES_SEM_ORGANIZACAO)(
    "sem organização ativa (%s) recusa com FORBIDDEN e NÃO toca o repositório",
    async (_nome, resolver) => {
      const repositorio = repositorioFalso();
      const servico = criarServiceColaboradores({ repositorio, organizacaoAtivaId: resolver });

      const resultado = await servico.listar({});

      expect(resultado).toEqual({
        ok: false,
        codigo: "FORBIDDEN",
        mensagem: "Selecione uma organização ativa para operar colaboradores.",
      });
      expect(repositorio.chamadas).toEqual([]);
    }
  );

  it("organização informada vazia (`\"\"`) não é intenção: cai para a ATIVA", async () => {
    const repositorio = repositorioFalso();
    const servico = servicoCom(repositorio);

    const resultado = await servico.listar({ organizationId: "" });

    expect(resultado.ok).toBe(true);
    expect(repositorio.chamadas).toEqual([{ metodo: "listar", argumentos: { organizationId: ORG } }]);
  });
});

describe("F5-07 service — normalização da projeção soberana", () => {
  it("obter devolve a PROJEÇÃO e não vaza o payload cru do servidor", async () => {
    const repositorio = repositorioFalso();
    const servico = servicoCom(repositorio);

    const resultado = await servico.obter({ collaboratorId: COLABORADOR });

    expect(resultado).toEqual({ ok: true, dados: colaboradorSoberano() });
    expect(JSON.stringify(resultado)).not.toContain("coluna_interna");
    expect(JSON.stringify(resultado)).not.toContain("resultadoCru");
  });

  it("obter propaga a matrícula como INTENÇÃO (resolução é server-side)", async () => {
    const repositorio = repositorioFalso();
    const servico = servicoCom(repositorio);

    await servico.obter({ matricula: "1234", dataReferencia: "2026-01-31" });

    expect(repositorio.chamadas[0]).toEqual({
      metodo: "obter",
      argumentos: { organizationId: ORG, matricula: "1234", dataReferencia: "2026-01-31" },
    });
  });

  it("listar não envia chaves opcionais vazias (payload mínimo)", async () => {
    const repositorio = repositorioFalso();
    const servico = servicoCom(repositorio);

    await servico.listar({ organizationId: ORG, busca: "" });

    expect(repositorio.chamadas[0]?.argumentos).toEqual({ organizationId: ORG });
  });

  it("obterHistorico envia apenas organização, colaborador e reservados informados", async () => {
    const repositorio = repositorioFalso();
    const servico = servicoCom(repositorio);

    await servico.obterHistorico({ collaboratorId: COLABORADOR, referenceCycleId: CICLO });

    expect(repositorio.chamadas[0]).toEqual({
      metodo: "obterHistorico",
      argumentos: { organizationId: ORG, collaboratorId: COLABORADOR, referenceCycleId: CICLO },
    });
  });
});

describe("F5-07 service — propagação da intenção em TODAS as operações", () => {
  const CASOS: ReadonlyArray<{
    readonly nome: string;
    readonly metodo: string;
    readonly executar: (servico: ServiceColaboradores) => Promise<unknown>;
    readonly esperado: Record<string, unknown>;
  }> = [
    {
      nome: "criar",
      metodo: "criar",
      executar: (servico) =>
        servico.criar({
          operationId: OPERACAO_ID,
          fullName: "Maria Silva",
          email: "maria@example.invalid",
          matricula: "1234",
          admissionDate: "2024-02-01",
          statusInicial: "leave",
        }),
      esperado: {
        organizationId: ORG,
        operationId: OPERACAO_ID,
        fullName: "Maria Silva",
        email: "maria@example.invalid",
        matricula: "1234",
        admissionDate: "2024-02-01",
        statusInicial: "leave",
      },
    },
    {
      nome: "editar",
      metodo: "editar",
      executar: (servico) =>
        servico.editar({
          operationId: OPERACAO_ID,
          collaboratorId: COLABORADOR,
          expectedVersion: 3,
          email: "novo@example.invalid",
        }),
      esperado: {
        organizationId: ORG,
        operationId: OPERACAO_ID,
        collaboratorId: COLABORADOR,
        expectedVersion: 3,
        email: "novo@example.invalid",
      },
    },
    {
      nome: "definirIdentificador",
      metodo: "definirIdentificador",
      executar: (servico) =>
        servico.definirIdentificador({
          operationId: OPERACAO_ID,
          collaboratorId: COLABORADOR,
          novaMatricula: "9999",
          vigencia: VIGENCIA,
          motivo: "troca",
          expectedVersion: 1,
        }),
      esperado: {
        organizationId: ORG,
        operationId: OPERACAO_ID,
        collaboratorId: COLABORADOR,
        novaMatricula: "9999",
        vigencia: VIGENCIA,
        motivo: "troca",
        expectedVersion: 1,
      },
    },
    {
      nome: "alterarStatus",
      metodo: "alterarStatus",
      executar: (servico) =>
        servico.alterarStatus({
          operationId: OPERACAO_ID,
          collaboratorId: COLABORADOR,
          novoStatus: "inactive",
          vigencia: VIGENCIA,
          motivo: "desligamento",
          expectedVersion: 2,
          cycleScope: "SOMENTE_CICLOS_POSTERIORES",
          referenceCycleId: CICLO,
        }),
      esperado: {
        organizationId: ORG,
        operationId: OPERACAO_ID,
        collaboratorId: COLABORADOR,
        novoStatus: "inactive",
        vigencia: VIGENCIA,
        motivo: "desligamento",
        expectedVersion: 2,
        cycleScope: "SOMENTE_CICLOS_POSTERIORES",
        referenceCycleId: CICLO,
      },
    },
    {
      nome: "definirOcupacao",
      metodo: "definirOcupacao",
      executar: (servico) =>
        servico.definirOcupacao({
          operationId: OPERACAO_ID,
          collaboratorId: COLABORADOR,
          positionId: POSICAO,
          vigencia: VIGENCIA,
          motivo: "movimentação",
        }),
      esperado: {
        organizationId: ORG,
        operationId: OPERACAO_ID,
        collaboratorId: COLABORADOR,
        positionId: POSICAO,
        vigencia: VIGENCIA,
        motivo: "movimentação",
      },
    },
    {
      nome: "encerrarOcupacao",
      metodo: "encerrarOcupacao",
      executar: (servico) =>
        servico.encerrarOcupacao({
          operationId: OPERACAO_ID,
          collaboratorId: COLABORADOR,
          vigencia: VIGENCIA,
          motivo: "fim",
        }),
      esperado: {
        organizationId: ORG,
        operationId: OPERACAO_ID,
        collaboratorId: COLABORADOR,
        vigencia: VIGENCIA,
        motivo: "fim",
      },
    },
    {
      nome: "definirReportingLine",
      metodo: "definirReportingLine",
      executar: (servico) =>
        servico.definirReportingLine({
          operationId: OPERACAO_ID,
          subordinatePositionId: POSICAO,
          managerPositionId: RESPONSABILIDADE,
          vigencia: VIGENCIA,
          motivo: "novo gestor",
        }),
      esperado: {
        organizationId: ORG,
        operationId: OPERACAO_ID,
        subordinatePositionId: POSICAO,
        managerPositionId: RESPONSABILIDADE,
        vigencia: VIGENCIA,
        motivo: "novo gestor",
      },
    },
    {
      nome: "encerrarReportingLine",
      metodo: "encerrarReportingLine",
      executar: (servico) =>
        servico.encerrarReportingLine({
          operationId: OPERACAO_ID,
          subordinatePositionId: POSICAO,
          vigencia: VIGENCIA,
          motivo: "sem gestor",
        }),
      esperado: {
        organizationId: ORG,
        operationId: OPERACAO_ID,
        subordinatePositionId: POSICAO,
        vigencia: VIGENCIA,
        motivo: "sem gestor",
      },
    },
    {
      nome: "definirResponsabilidade",
      metodo: "definirResponsabilidade",
      executar: (servico) =>
        servico.definirResponsabilidade({
          operationId: OPERACAO_ID,
          positionId: POSICAO,
          substituteCollaboratorId: COLABORADOR,
          responsibilityType: "operational_evaluative",
          vigencia: VIGENCIA,
          motivo: "férias",
        }),
      esperado: {
        organizationId: ORG,
        operationId: OPERACAO_ID,
        positionId: POSICAO,
        substituteCollaboratorId: COLABORADOR,
        responsibilityType: "operational_evaluative",
        vigencia: VIGENCIA,
        motivo: "férias",
      },
    },
    {
      nome: "encerrarResponsabilidade",
      metodo: "encerrarResponsabilidade",
      executar: (servico) =>
        servico.encerrarResponsabilidade({
          operationId: OPERACAO_ID,
          responsibilityId: RESPONSABILIDADE,
          vigencia: VIGENCIA,
          motivo: "retorno",
        }),
      esperado: {
        organizationId: ORG,
        operationId: OPERACAO_ID,
        responsibilityId: RESPONSABILIDADE,
        vigencia: VIGENCIA,
        motivo: "retorno",
      },
    },
    {
      nome: "registrarSucessao",
      metodo: "registrarSucessao",
      executar: (servico) =>
        servico.registrarSucessao({
          operationId: OPERACAO_ID,
          responsibilityIds: [RESPONSABILIDADE],
          successionDate: VIGENCIA,
          motivo: "sucessão",
        }),
      esperado: {
        organizationId: ORG,
        operationId: OPERACAO_ID,
        responsibilityIds: [RESPONSABILIDADE],
        successionDate: VIGENCIA,
        motivo: "sucessão",
      },
    },
    {
      nome: "bootstrapCatalogo",
      metodo: "bootstrapCatalogo",
      executar: (servico) =>
        servico.bootstrapCatalogo({
          operationId: OPERACAO_ID,
          catalogo: { jobRoles: [{ code: "GERENTE", name: "Gerente" }], seniorityLevels: ["Pleno"] },
        }),
      esperado: {
        organizationId: ORG,
        operationId: OPERACAO_ID,
        catalogo: { jobRoles: [{ code: "GERENTE", name: "Gerente" }], seniorityLevels: ["Pleno"] },
      },
    },
  ];

  it.each(CASOS)("propaga a intenção de %s com a organização resolvida", async (caso) => {
    const repositorio = repositorioFalso();
    const servico = servicoCom(repositorio);

    const resultado = await caso.executar(servico);

    expect(resultado).toMatchObject({ ok: true });
    expect(repositorio.chamadas).toHaveLength(1);
    expect(repositorio.chamadas[0]?.metodo).toBe(caso.metodo);
    expect(repositorio.chamadas[0]?.argumentos).toEqual(caso.esperado);
  });

  it("cobre as 12 mutações + histórico do contrato (sem operação esquecida)", () => {
    const metodos = CASOS.map((caso) => caso.metodo).sort();
    expect(metodos).toEqual(
      [
        "alterarStatus",
        "bootstrapCatalogo",
        "criar",
        "definirIdentificador",
        "definirOcupacao",
        "definirReportingLine",
        "definirResponsabilidade",
        "editar",
        "encerrarOcupacao",
        "encerrarReportingLine",
        "encerrarResponsabilidade",
        "registrarSucessao",
      ].sort()
    );
  });
});

describe("F5-07 service — negação vira resultado, nunca exceção", () => {
  it.each([
    ["NOT_FOUND", "Colaborador não encontrado."],
    ["FORBIDDEN", "Você não tem permissão para esta operação."],
    ["CONFLICT", "detalhe interno do banco"],
    ["INVALID_INPUT", "detalhe interno do banco"],
    ["NOT_AUTHORIZED", "Sessão inválida. Entre novamente."],
    ["METHOD_NOT_ALLOWED", "Operação indisponível neste ambiente."],
    ["INTERNAL", "Não foi possível concluir a operação."],
  ] as const)("mapeia %s para o código público sem lançar", async (code, mensagem) => {
    const repositorio = repositorioFalso(falhaRepositorio(code));
    const servico = servicoCom(repositorio);

    const resultado = await servico.listar({});

    expect(resultado).toEqual({ ok: false, codigo: code, mensagem });
  });

  it("FORBIDDEN/NOT_FOUND nunca ecoam a mensagem crua do servidor", async () => {
    for (const code of ["FORBIDDEN", "NOT_FOUND"] as const) {
      const repositorio = repositorioFalso(falhaRepositorio(code, "F5_07_FORBIDDEN: ator sem vinculo"));
      const servico = servicoCom(repositorio);

      const resultado = await servico.listar({});

      expect(resultado.ok).toBe(false);
      if (resultado.ok) return;
      expect(resultado.mensagem).not.toContain("F5_07");
      expect(resultado.mensagem).not.toContain("vinculo");
    }
  });

  it("`mensagemColaboradores` é fail-closed para código desconhecido", () => {
    expect(
      mensagemColaboradores({ code: "INTERNAL", message: "x" })
    ).toBe("Não foi possível concluir a operação.");
  });

  it("nenhuma operação escreve em localStorage (sucesso e negação)", async () => {
    const sucesso = servicoCom(repositorioFalso());
    await sucesso.listar({});
    await sucesso.obter({ collaboratorId: COLABORADOR });
    await sucesso.criar({
      operationId: OPERACAO_ID,
      fullName: "Maria",
      email: "maria@example.invalid",
      matricula: "1234",
    });

    const negado = servicoCom(repositorioFalso(falhaRepositorio("FORBIDDEN")));
    await negado.listar({});
    await negado.obter({ collaboratorId: COLABORADOR });

    expect(armazenamento.length).toBe(0);
    expect(armazenamento.key(0)).toBeNull();
  });
});

describe("F5-07 service — fail-closed sem configuração de ambiente", () => {
  it("sem repositório injetado e sem VITE_* ⇒ INTERNAL (nunca localStorage)", async () => {
    vi.resetModules();
    vi.stubEnv("VITE_SUPABASE_URL", undefined);
    vi.stubEnv("VITE_SUPABASE_ANON_KEY", undefined);
    const modulo = await import("./serviceColaboradores");
    const servico = modulo.criarServiceColaboradores({ organizacaoAtivaId: () => ORG });

    const resultado = await servico.listar({});

    expect(resultado).toEqual({
      ok: false,
      codigo: "INTERNAL",
      mensagem: "O caminho de colaboradores no PostgreSQL não está disponível neste ambiente.",
    });
    expect(armazenamento.length).toBe(0);
  });

  it("`criarRepositorioColaboradoresProducao` devolve null sem cliente/configuração", () => {
    vi.resetModules();
    vi.stubEnv("VITE_SUPABASE_URL", undefined);
    vi.stubEnv("VITE_SUPABASE_ANON_KEY", undefined);
    expect(criarRepositorioColaboradoresProducao(null)).toBeNull();
  });

  it("com cliente injetado usa a Edge `colaboradores` e traduz a resposta (sem rede)", async () => {
    const invocacoes: { readonly nome: string; readonly corpo: unknown }[] = [];
    const cliente = {
      functions: {
        invoke: (nome: string, opcoes: { body: unknown }) => {
          invocacoes.push({ nome, corpo: opcoes.body });
          return Promise.resolve({
            data: {
              ok: true,
              operacao: "collaborator.listar",
              // Linha CRUA da projeção (snake_case), como a Edge devolve.
              resultado: [
                {
                  collaborator_id: COLABORADOR,
                  matricula: "1234",
                  full_name: "Maria Silva",
                  email: "maria@example.invalid",
                  status: "active",
                  admission_date: "2024-02-01",
                  unit_id: POSICAO,
                  unit_name: "Unidade Fictícia",
                  job_role_code: "ANALISTA",
                  job_role_name: "Analista",
                  seniority_name: "Pleno",
                  manager_collaborator_id: null,
                  manager_full_name: null,
                  version: 3,
                },
              ],
            },
            error: null,
          });
        },
      },
    } as unknown as SupabaseClient;

    const servico = criarServiceColaboradores({
      cliente,
      organizacaoAtivaId: () => ORG,
    });

    const resultado = await servico.listar({ busca: "silva" });

    expect(resultado).toEqual({ ok: true, dados: [colaboradorSoberano()] });
    expect(invocacoes).toEqual([
      {
        nome: "colaboradores",
        corpo: {
          operacao: "collaborator.listar",
          organization_id: ORG,
          filtros: { busca: "silva" },
        },
      },
    ]);
  });
});
