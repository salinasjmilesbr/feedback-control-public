import { beforeEach, describe, expect, it } from "vitest";
import * as porta from "./acessoColaboradoresSoberanos";
import {
  obterOperacoesColaboradoresSoberanos,
  redefinirAcessoColaboradoresSoberanos,
  type DependenciasAcessoColaboradores,
} from "./acessoColaboradoresSoberanos";
import portaFonte from "./acessoColaboradoresSoberanos.ts?raw";
import { instalarLocalStorageEmMemoria } from "../../test/localStorageMock";
import type { ServiceColaboradores } from "./serviceColaboradores";
import type {
  ColaboradorSoberano,
  EventoColaborador,
} from "../../infrastructure/supabase/colaboradores/repositorioColaboradores";
import type { EstruturaSoberana } from "../../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";

/**
 * F5-07 — PORTA ÚNICA das telas (§3).
 *
 * A porta é a única superfície que as páginas conhecem: ela resolve a
 * organização ativa (INTENÇÃO), injeta as operações soberanas e transforma
 * QUALQUER falha em `ResultadoColaboradores`. O que este teste prova:
 * - os 15 exports exatos da espinha e a propagação fiel dos argumentos;
 * - negação (`FORBIDDEN`/`NOT_FOUND`/...) nunca vira exceção;
 * - falha inesperada do service vira `INTERNAL` (nunca `localStorage`);
 * - memoização/injeção (`obterOperacoesColaboradoresSoberanos` /
 *   `redefinirAcessoColaboradoresSoberanos`) se comporta como documentado;
 * - o módulo não conhece Supabase, autorização nem armazenamento local.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const OUTRA_ORG = "99999999-9999-4999-8999-999999999999";
const COLABORADOR = "22222222-2222-4222-8222-222222222222";
const POSICAO = "33333333-3333-4333-8333-333333333333";
const GESTOR = "77777777-7777-4777-8777-777777777777";
const CICLO = "55555555-5555-4555-8555-555555555555";
const OPERACAO_ID = "66666666-6666-4666-8666-666666666666";
const RESPONSABILIDADE = "88888888-8888-4888-8888-888888888888";
const VIGENCIA = "2026-03-01T00:00:00.000Z";
const MOTIVO = "ajuste contratual";

function colaboradorSoberano(): ColaboradorSoberano {
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

/** F5-08 P4 — identidade fictícia devolvida pelas operações de estrutura. */
const NOVA_UNIDADE = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";

/** Fotografia estrutural fictícia (leitura soberana injetada). */
function estruturaSoberana(): EstruturaSoberana {
  return {
    unidades: [
      { unitId: POSICAO, nome: "Unidade Fictícia", validFrom: VIGENCIA, validTo: null, version: 2 },
    ],
    periodosParent: [],
    posicoes: [],
    reportingLines: [],
    ocupacoes: [],
    cargos: [],
    senioridades: [],
    colegiados: [],
    colaboradores: [{ collaboratorId: COLABORADOR, nome: "Maria Silva" }],
  };
}

type Chamada = {
  readonly metodo: string;
  readonly argumentos: unknown;
};

type ServicoFalso = ServiceColaboradores & { readonly chamadas: readonly Chamada[] };

/** Service FAKE com registro de chamadas (nenhuma rede). */
function servicoFalso(
  comportamentos: Partial<ServiceColaboradores> = {}
): ServicoFalso {
  const chamadas: Chamada[] = [];
  const registrar = <T>(metodo: string, argumentos: unknown, dados: T) => {
    chamadas.push({ metodo, argumentos });
    return Promise.resolve({ ok: true, dados } as const);
  };

  const padrao: ServiceColaboradores = {
    listar: (entrada) => registrar("listar", entrada, [colaboradorSoberano()]),
    obter: (entrada) => registrar("obter", entrada, colaboradorSoberano()),
    criar: (entrada) => registrar("criar", entrada, COLABORADOR),
    editar: (entrada) => registrar("editar", entrada, 4),
    definirIdentificador: (entrada) => registrar("definirIdentificador", entrada, 5),
    alterarStatus: (entrada) => registrar("alterarStatus", entrada, 4),
    definirOcupacao: (entrada) => registrar("definirOcupacao", entrada, POSICAO),
    encerrarOcupacao: (entrada) => registrar("encerrarOcupacao", entrada, null),
    definirReportingLine: (entrada) => registrar("definirReportingLine", entrada, POSICAO),
    encerrarReportingLine: (entrada) => registrar("encerrarReportingLine", entrada, null),
    definirResponsabilidade: (entrada) => registrar("definirResponsabilidade", entrada, RESPONSABILIDADE),
    encerrarResponsabilidade: (entrada) => registrar("encerrarResponsabilidade", entrada, null),
    registrarSucessao: (entrada) => registrar("registrarSucessao", entrada, null),
    obterHistorico: (entrada) => registrar("obterHistorico", entrada, [eventoColaborador()]),
    bootstrapCatalogo: (entrada) => registrar("bootstrapCatalogo", entrada, null),
    // F5-08 P4 — leitura soberana (RLS/D16) e 15 operações administrativas.
    lerEstrutura: (entrada) => registrar("lerEstrutura", entrada, estruturaSoberana()),
    criarUnidade: (entrada) => registrar("criarUnidade", entrada, NOVA_UNIDADE),
    renomearUnidade: (entrada) => registrar("renomearUnidade", entrada, 1),
    encerrarUnidade: (entrada) => registrar("encerrarUnidade", entrada, 2),
    definirParentUnidade: (entrada) => registrar("definirParentUnidade", entrada, NOVA_UNIDADE),
    encerrarParentUnidade: (entrada) => registrar("encerrarParentUnidade", entrada, NOVA_UNIDADE),
    criarPosicao: (entrada) => registrar("criarPosicao", entrada, POSICAO),
    encerrarPosicao: (entrada) => registrar("encerrarPosicao", entrada, 3),
    definirColegiado: (entrada) => registrar("definirColegiado", entrada, NOVA_UNIDADE),
    encerrarColegiado: (entrada) => registrar("encerrarColegiado", entrada, NOVA_UNIDADE),
    criarCargo: (entrada) => registrar("criarCargo", entrada, NOVA_UNIDADE),
    renomearCargo: (entrada) => registrar("renomearCargo", entrada, 4),
    alterarStatusCargo: (entrada) => registrar("alterarStatusCargo", entrada, 5),
    criarSenioridade: (entrada) => registrar("criarSenioridade", entrada, NOVA_UNIDADE),
    renomearSenioridade: (entrada) => registrar("renomearSenioridade", entrada, 6),
    alterarStatusSenioridade: (entrada) => registrar("alterarStatusSenioridade", entrada, 7),
  };

  return { ...padrao, ...comportamentos, chamadas };
}

const ENTRADAS = {
  listar: {
    organizationId: OUTRA_ORG,
    dataReferencia: "2026-01-31",
    status: "active",
    unitId: POSICAO,
    busca: "silva",
  },
  obter: { collaboratorId: COLABORADOR, matricula: undefined, organizationId: ORG },
  historico: { collaboratorId: COLABORADOR, referenceCycleId: CICLO },
  criar: {
    fullName: "Maria Silva",
    email: "maria@example.invalid",
    matricula: "1234",
    operationId: OPERACAO_ID,
    admissionDate: "2024-02-01",
    statusInicial: "leave" as const,
    organizationId: OUTRA_ORG,
  },
  editar: {
    collaboratorId: COLABORADOR,
    operationId: OPERACAO_ID,
    expectedVersion: 3,
    email: "novo@example.invalid",
    organizationId: ORG,
  },
  identificador: {
    collaboratorId: COLABORADOR,
    operationId: OPERACAO_ID,
    novaMatricula: "9999",
    vigencia: VIGENCIA,
    motivo: MOTIVO,
    expectedVersion: 1,
    organizationId: ORG,
  },
  status: {
    collaboratorId: COLABORADOR,
    operationId: OPERACAO_ID,
    novoStatus: "inactive" as const,
    vigencia: VIGENCIA,
    motivo: MOTIVO,
    expectedVersion: 2,
    cycleScope: "SOMENTE_CICLOS_POSTERIORES" as const,
    referenceCycleId: CICLO,
    organizationId: ORG,
  },
  ocupacao: {
    collaboratorId: COLABORADOR,
    operationId: OPERACAO_ID,
    positionId: POSICAO,
    vigencia: VIGENCIA,
    motivo: MOTIVO,
    organizationId: ORG,
  },
  encerrarOcupacao: {
    collaboratorId: COLABORADOR,
    operationId: OPERACAO_ID,
    vigencia: VIGENCIA,
    motivo: MOTIVO,
    organizationId: ORG,
  },
  reporting: {
    subordinatePositionId: POSICAO,
    managerPositionId: GESTOR,
    operationId: OPERACAO_ID,
    vigencia: VIGENCIA,
    motivo: MOTIVO,
    organizationId: ORG,
  },
  encerrarReporting: {
    subordinatePositionId: POSICAO,
    operationId: OPERACAO_ID,
    vigencia: VIGENCIA,
    motivo: MOTIVO,
    organizationId: ORG,
  },
  responsabilidade: {
    positionId: POSICAO,
    substituteCollaboratorId: COLABORADOR,
    responsibilityType: "evaluative" as const,
    operationId: OPERACAO_ID,
    vigencia: VIGENCIA,
    motivo: MOTIVO,
    organizationId: ORG,
  },
  encerrarResponsabilidade: {
    responsibilityId: RESPONSABILIDADE,
    operationId: OPERACAO_ID,
    vigencia: VIGENCIA,
    motivo: MOTIVO,
    organizationId: ORG,
  },
  sucessao: {
    responsibilityIds: [RESPONSABILIDADE],
    successionDate: VIGENCIA,
    operationId: OPERACAO_ID,
    motivo: MOTIVO,
    organizationId: ORG,
  },
  catalogo: {
    operationId: OPERACAO_ID,
    jobRoles: [{ code: "GERENTE", name: "Gerente" }],
    seniorityLevels: ["Pleno"],
    organizationId: OUTRA_ORG,
  },
} as const;

interface CasoDaPorta {
  readonly nome: string;
  readonly metodo: string;
  readonly chamar: (deps: DependenciasAcessoColaboradores) => Promise<unknown>;
  readonly argumentos: unknown;
}

/** Os 15 exports da espinha §3, com o argumento EXATO esperado no service. */
const CASOS_DA_PORTA: readonly CasoDaPorta[] = [
  {
    nome: "listarColaboradores",
    metodo: "listar",
    chamar: (deps) => porta.listarColaboradores(ENTRADAS.listar, deps),
    argumentos: ENTRADAS.listar,
  },
  {
    nome: "obterColaborador",
    metodo: "obter",
    chamar: (deps) => porta.obterColaborador(ENTRADAS.obter, deps),
    argumentos: ENTRADAS.obter,
  },
  {
    nome: "obterHistoricoColaborador",
    metodo: "obterHistorico",
    chamar: (deps) => porta.obterHistoricoColaborador(ENTRADAS.historico, deps),
    argumentos: ENTRADAS.historico,
  },
  {
    nome: "criarColaborador",
    metodo: "criar",
    chamar: (deps) => porta.criarColaborador(ENTRADAS.criar, deps),
    argumentos: ENTRADAS.criar,
  },
  {
    nome: "editarColaborador",
    metodo: "editar",
    chamar: (deps) => porta.editarColaborador(ENTRADAS.editar, deps),
    argumentos: ENTRADAS.editar,
  },
  {
    nome: "alterarStatusColaborador",
    metodo: "alterarStatus",
    chamar: (deps) => porta.alterarStatusColaborador(ENTRADAS.status, deps),
    argumentos: ENTRADAS.status,
  },
  {
    nome: "definirIdentificadorColaborador",
    metodo: "definirIdentificador",
    chamar: (deps) => porta.definirIdentificadorColaborador(ENTRADAS.identificador, deps),
    argumentos: ENTRADAS.identificador,
  },
  {
    nome: "definirOcupacao",
    metodo: "definirOcupacao",
    chamar: (deps) => porta.definirOcupacao(ENTRADAS.ocupacao, deps),
    argumentos: ENTRADAS.ocupacao,
  },
  {
    nome: "encerrarOcupacao",
    metodo: "encerrarOcupacao",
    chamar: (deps) => porta.encerrarOcupacao(ENTRADAS.encerrarOcupacao, deps),
    argumentos: ENTRADAS.encerrarOcupacao,
  },
  {
    nome: "definirReportingLine",
    metodo: "definirReportingLine",
    chamar: (deps) => porta.definirReportingLine(ENTRADAS.reporting, deps),
    argumentos: ENTRADAS.reporting,
  },
  {
    nome: "encerrarReportingLine",
    metodo: "encerrarReportingLine",
    chamar: (deps) => porta.encerrarReportingLine(ENTRADAS.encerrarReporting, deps),
    argumentos: ENTRADAS.encerrarReporting,
  },
  {
    nome: "definirResponsabilidadeTemporaria",
    metodo: "definirResponsabilidade",
    chamar: (deps) => porta.definirResponsabilidadeTemporaria(ENTRADAS.responsabilidade, deps),
    argumentos: ENTRADAS.responsabilidade,
  },
  {
    nome: "encerrarResponsabilidadeTemporaria",
    metodo: "encerrarResponsabilidade",
    chamar: (deps) => porta.encerrarResponsabilidadeTemporaria(ENTRADAS.encerrarResponsabilidade, deps),
    argumentos: ENTRADAS.encerrarResponsabilidade,
  },
  {
    nome: "registrarSucessao",
    metodo: "registrarSucessao",
    chamar: (deps) => porta.registrarSucessao(ENTRADAS.sucessao, deps),
    argumentos: ENTRADAS.sucessao,
  },
  {
    nome: "bootstrapCatalogo",
    metodo: "bootstrapCatalogo",
    chamar: (deps) => porta.bootstrapCatalogo(ENTRADAS.catalogo, deps),
    // A porta TRADUZ `jobRoles`/`seniorityLevels` para o catálogo do contrato.
    argumentos: {
      operationId: OPERACAO_ID,
      catalogo: { jobRoles: [{ code: "GERENTE", name: "Gerente" }], seniorityLevels: ["Pleno"] },
      organizationId: OUTRA_ORG,
    },  },
];

const EXPORTS_DA_PORTA = CASOS_DA_PORTA.map((caso) => caso.nome).sort();

/**
 * F5-08 P4 — superfície ADICIONADA pela administração de estrutura/catálogo
 * (leitura soberana + as 15 operações administrativas do P3). O comportamento
 * de cada uma é exercitado em `acessoEstruturaSoberana.test.ts`.
 */
const EXPORTS_P4 = [
  "lerEstrutura",
  "criarUnidade",
  "renomearUnidade",
  "encerrarUnidade",
  "definirParentUnidade",
  "encerrarParentUnidade",
  "criarPosicao",
  "encerrarPosicao",
  "definirColegiado",
  "encerrarColegiado",
  "criarCargo",
  "renomearCargo",
  "alterarStatusCargo",
  "criarSenioridade",
  "renomearSenioridade",
  "alterarStatusSenioridade",
].sort();

const AUXILIARES = ["obterOperacoesColaboradoresSoberanos", "redefinirAcessoColaboradoresSoberanos"];

const NEGADO = {
  ok: false as const,
  codigo: "FORBIDDEN" as const,
  mensagem: "Você não tem permissão para esta operação.",
};

function servicoQueNega(): ServiceColaboradores {
  const negar = () => Promise.resolve(NEGADO);
  return {
    listar: negar,
    obter: negar,
    criar: negar,
    editar: negar,
    definirIdentificador: negar,
    alterarStatus: negar,
    definirOcupacao: negar,
    encerrarOcupacao: negar,
    definirReportingLine: negar,
    encerrarReportingLine: negar,
    definirResponsabilidade: negar,
    encerrarResponsabilidade: negar,
    registrarSucessao: negar,
    obterHistorico: negar,
    bootstrapCatalogo: negar,
  } as unknown as ServiceColaboradores;
}

function servicoQueLanca(): ServiceColaboradores {
  const lancar = () => Promise.reject(new Error("rede indisponível"));
  return {
    listar: lancar,
    obter: lancar,
    criar: lancar,
    editar: lancar,
    definirIdentificador: lancar,
    alterarStatus: lancar,
    definirOcupacao: lancar,
    encerrarOcupacao: lancar,
    definirReportingLine: lancar,
    encerrarReportingLine: lancar,
    definirResponsabilidade: lancar,
    encerrarResponsabilidade: lancar,
    registrarSucessao: lancar,
    obterHistorico: lancar,
    bootstrapCatalogo: lancar,
  } as unknown as ServiceColaboradores;
}

let armazenamento: Storage;

/** Código sem comentários (de bloco e de linha) — a barreira é o CÓDIGO. */
function apenasCodigo(fonte: string): string {
  return fonte
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf("//");
      return indice === -1 ? linha : linha.slice(0, indice);
    })
    .join("\n");
}

beforeEach(() => {
  armazenamento = instalarLocalStorageEmMemoria();
  redefinirAcessoColaboradoresSoberanos();
});

describe("F5-07 porta — superfície EXATA da espinha §3", () => {
  it("expõe os 15 exports da espinha + os 16 do P4 (e nenhuma função além deles)", () => {
    const funcoes = Object.entries(porta as unknown as Record<string, unknown>)
      .filter(([, valor]) => typeof valor === "function")
      .map(([nome]) => nome);

    expect(funcoes.filter((nome) => !AUXILIARES.includes(nome)).sort()).toEqual(
      [...EXPORTS_DA_PORTA, ...EXPORTS_P4].sort()
    );
    for (const nome of [...EXPORTS_DA_PORTA, ...EXPORTS_P4]) {
      expect(typeof (porta as unknown as Record<string, unknown>)[nome], nome).toBe("function");
    }
  });

  it("não conhece Supabase, autorização nem armazenamento local", () => {
    const codigo = apenasCodigo(portaFonte as string);
    expect(codigo).not.toContain("localStorage");
    expect(codigo).not.toContain("@supabase");
    expect(codigo).not.toContain("functions.invoke");
    expect(codigo).not.toContain("capability");
    expect(codigo).not.toContain("Policy Engine");
  });
});

describe("F5-07 porta — propagação fiel dos argumentos ao service injetado", () => {
  it.each(CASOS_DA_PORTA)("$nome propaga a intenção sem alterá-la", async (caso) => {
    const servico = servicoFalso();
    const resultado = await caso.chamar({ operacoes: servico });

    expect(resultado).toMatchObject({ ok: true });
    expect(servico.chamadas).toHaveLength(1);
    expect(servico.chamadas[0]?.metodo).toBe(caso.metodo);
    expect(servico.chamadas[0]?.argumentos).toEqual(caso.argumentos);
  });

  it("bootstrapCatalogo NÃO inventa estrutura: envia só jobRoles e seniorityLevels (D16)", async () => {
    const servico = servicoFalso();
    await porta.bootstrapCatalogo(ENTRADAS.catalogo, { operacoes: servico });

    const argumentos = servico.chamadas[0]?.argumentos as {
      readonly catalogo: Record<string, unknown>;
    };
    expect(Object.keys(argumentos.catalogo).sort()).toEqual(["jobRoles", "seniorityLevels"]);
  });
});

describe("F5-07 porta — negação nunca é exceção", () => {
  it.each(CASOS_DA_PORTA)("$nome devolve o código público sem lançar", async (caso) => {
    const resultado = await caso.chamar({ operacoes: servicoQueNega() });

    expect(resultado).toEqual(NEGADO);
  });

  it("NOT_FOUND/CONFLICT também voltam como resultado (indistinguíveis de exceção)", async () => {
    const naoEncontrado = {
      ok: false as const,
      codigo: "NOT_FOUND" as const,
      mensagem: "Colaborador não encontrado.",
    };
    const servico = servicoFalso({
      obter: () => Promise.resolve(naoEncontrado),
    });

    await expect(porta.obterColaborador({ collaboratorId: COLABORADOR }, { operacoes: servico })).resolves.toEqual(
      naoEncontrado
    );
    // Nenhuma exceção escapou e nada foi persistido localmente.
    expect(armazenamento.length).toBe(0);
  });

  it.each(CASOS_DA_PORTA)("$nome converte falha inesperada em INTERNAL", async (caso) => {
    const resultado = await caso.chamar({ operacoes: servicoQueLanca() });

    expect(resultado).toEqual({
      ok: false,
      codigo: "INTERNAL",
      mensagem: "Não foi possível concluir a operação de colaborador.",
    });
  });

  it("nenhuma operação da porta escreve em localStorage (sucesso, negação e falha)", async () => {
    for (const caso of CASOS_DA_PORTA) {
      await caso.chamar({ operacoes: servicoFalso() });
      await caso.chamar({ operacoes: servicoQueNega() });
      await caso.chamar({ operacoes: servicoQueLanca() });
    }

    expect(armazenamento.length).toBe(0);
    expect(armazenamento.key(0)).toBeNull();
  });
});

describe("F5-07 porta — memoização e injeção do caminho soberano", () => {
  it("memoiza a instância resolvida (deps posteriores são ignoradas)", () => {
    const primeiro = obterOperacoesColaboradoresSoberanos({ deps: { organizacaoAtivaId: () => ORG } });
    const segundo = obterOperacoesColaboradoresSoberanos({
      deps: { organizacaoAtivaId: () => OUTRA_ORG },
    });

    expect(primeiro).not.toBeNull();
    expect(segundo).toBe(primeiro);
  });

  it("`redefinirAcessoColaboradoresSoberanos` descarta a memoização", () => {
    const primeiro = obterOperacoesColaboradoresSoberanos({ deps: {} });
    redefinirAcessoColaboradoresSoberanos();
    const segundo = obterOperacoesColaboradoresSoberanos({ deps: {} });

    expect(segundo).not.toBe(primeiro);
  });

  it("`operacoes` injetadas NÃO são memoizadas nem substituídas pela instância de produção", () => {
    const injetadoA = servicoFalso();
    const injetadoB = servicoFalso();

    expect(obterOperacoesColaboradoresSoberanos({ operacoes: injetadoA })).toBe(injetadoA);
    expect(obterOperacoesColaboradoresSoberanos({ operacoes: injetadoB })).toBe(injetadoB);

    const memoizado = obterOperacoesColaboradoresSoberanos({ deps: {} });
    expect(memoizado).not.toBe(injetadoA);
    expect(obterOperacoesColaboradoresSoberanos({ operacoes: injetadoA })).toBe(injetadoA);
  });

  it("as operações injetadas de fato recebem a chamada da porta", async () => {
    const servico = servicoFalso();
    redefinirAcessoColaboradoresSoberanos();

    await porta.listarColaboradores({ organizationId: ORG }, { operacoes: servico });

    expect(servico.chamadas.map((chamada) => chamada.metodo)).toEqual(["listar"]);
  });
});
