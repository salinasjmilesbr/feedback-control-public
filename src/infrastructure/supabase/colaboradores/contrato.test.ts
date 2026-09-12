import { describe, expect, it } from "vitest";
import {
  ehOperacaoColaborador,
  ehUuid,
  ID_NEUTRO,
  OPERACOES_COLABORADOR,
  validarEntradaColaborador,
  type OperacaoColaborador,
} from "./contrato";

/**
 * F5-07 (D1–D20) — validação de FORMA do contrato transportável (§8.2).
 *
 * A fronteira confiável NUNCA valida autoridade no corpo: este módulo só aceita
 * INTENÇÃO bem formada. Os testes cobrem:
 * - as 15 operações com payload válido (e a normalização resultante);
 * - UUID obrigatório, `expected_version` nas operações de linha existente,
 *   `operation_id` em toda mutação, `motivo` não vazio, domínios fechados;
 * - campos que tentariam PROVAR autoridade (`capability`, `role`, `scope`,
 *   identidade do ator) ⇒ `INVALID_INPUT`; `organization_id` continua aceito
 *   apenas como INTENÇÃO (a Edge a revalida contra a membership);
 * - o `alvo` enviado pela tela é IGNORADO (o alvo autorizável é soberano).
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const OUTRA_ORG = "99999999-9999-4999-8999-999999999999";
const COLABORADOR = "22222222-2222-4222-8222-222222222222";
const POSICAO = "33333333-3333-4333-8333-333333333333";
const OUTRA_POSICAO = "77777777-7777-4777-8777-777777777777";
const CICLO = "55555555-5555-4555-8555-555555555555";
const OPERACAO_ID = "66666666-6666-4666-8666-666666666666";
const RESPONSABILIDADE = "88888888-8888-4888-8888-888888888888";
const VIGENCIA = "2026-03-01T00:00:00.000Z";
const MOTIVO = "ajuste contratual";
// F5-08 P3 — identificadores das operações de estrutura/catálogo.
const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const OUTRA_UNIDADE = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const CARGO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const SENIORIDADE = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const MEMBRO_A = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const MEMBRO_B = "ffffffff-ffff-4fff-8fff-ffffffffffff";
const VALID_FROM = "2026-04-01T00:00:00.000Z";
const VALID_TO = "2026-05-01T00:00:00.000Z";

type Corpo = Record<string, unknown>;

/** Payload mínimo VÁLIDO por operação (espinha §2 / §8.1). */
const CASOS_VALIDOS: ReadonlyArray<readonly [string, Corpo]> = [
  [
    "collaborator.listar",
    {
      organization_id: ORG,
      data_referencia: "2026-01-31",
      filtros: { status: "active", unit_id: POSICAO, busca: "silva" },
    },
  ],
  ["collaborator.obter", { organization_id: ORG, collaborator_id: COLABORADOR }],
  ["collaborator.obter (por matrícula)", { organization_id: ORG, matricula: "1234" }],
  [
    "collaborator.criar",
    {
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      full_name: "  Maria Silva  ",
      email: "  maria@example.invalid ",
      matricula: "1234",
      admission_date: "2024-02-01",
      status_inicial: "leave",
    },
  ],
  [
    "collaborator.editar",
    {
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      collaborator_id: COLABORADOR,
      email: "novo@example.invalid",
      expected_version: 3,
    },
  ],
  [
    "collaborator.identificador.definir",
    {
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      collaborator_id: COLABORADOR,
      nova_matricula: "9999",
      vigencia: VIGENCIA,
      motivo: MOTIVO,
      expected_version: 1,
    },
  ],
  [
    "collaborator.status.alterar",
    {
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      collaborator_id: COLABORADOR,
      novo_status: "leave",
      vigencia: VIGENCIA,
      motivo: MOTIVO,
      cycle_scope: "SOMENTE_CICLOS_POSTERIORES",
      reference_cycle_id: CICLO,
      expected_version: 2,
    },
  ],
  [
    "colaborador.ocupacao.definir",
    {
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      collaborator_id: COLABORADOR,
      position_id: POSICAO,
      vigencia: VIGENCIA,
      motivo: MOTIVO,
    },
  ],
  [
    "colaborador.ocupacao.encerrar",
    {
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      collaborator_id: COLABORADOR,
      vigencia: VIGENCIA,
      motivo: MOTIVO,
    },
  ],
  [
    "estrutura.reporting.definir",
    {
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      subordinate_position_id: POSICAO,
      manager_position_id: OUTRA_POSICAO,
      vigencia: VIGENCIA,
      motivo: MOTIVO,
    },
  ],
  [
    "estrutura.reporting.encerrar",
    {
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      subordinate_position_id: POSICAO,
      vigencia: VIGENCIA,
      motivo: MOTIVO,
    },
  ],
  [
    "estrutura.responsabilidade.definir",
    {
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      position_id: POSICAO,
      substitute_collaborator_id: COLABORADOR,
      responsibility_type: "evaluative",
      vigencia: VIGENCIA,
      motivo: MOTIVO,
    },
  ],
  [
    "estrutura.responsabilidade.encerrar",
    {
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      responsibility_id: RESPONSABILIDADE,
      vigencia: VIGENCIA,
      motivo: MOTIVO,
    },
  ],
  [
    "estrutura.sucessao.registrar",
    {
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      responsibility_ids: [RESPONSABILIDADE],
      succession_date: VIGENCIA,
      motivo: MOTIVO,
    },
  ],
  // F5-08 P3 — estrutura organizacional (payload público camelCase).
  [
    "estrutura.unidade.criar",
    { organization_id: ORG, operationId: OPERACAO_ID, nome: "Unidade Nova", validFrom: VALID_FROM, motivo: MOTIVO },
  ],
  [
    "estrutura.unidade.renomear",
    { organization_id: ORG, operationId: OPERACAO_ID, unidadeId: UNIDADE, nome: "Unidade Renomeada", expectedVersion: 0, motivo: MOTIVO },
  ],
  [
    "estrutura.unidade.encerrar",
    { organization_id: ORG, operationId: OPERACAO_ID, unidadeId: UNIDADE, validTo: VALID_TO, expectedVersion: 1, motivo: MOTIVO },
  ],
  [
    "estrutura.unidade.parent.definir",
    { organization_id: ORG, operationId: OPERACAO_ID, unidadeId: UNIDADE, parentUnitId: OUTRA_UNIDADE, validFrom: VALID_FROM, motivo: MOTIVO },
  ],
  [
    "estrutura.unidade.parent.definir (raiz)",
    { organization_id: ORG, operationId: OPERACAO_ID, unidadeId: UNIDADE, parentUnitId: null, validFrom: VALID_FROM, motivo: MOTIVO },
  ],
  [
    "estrutura.unidade.parent.encerrar",
    { organization_id: ORG, operationId: OPERACAO_ID, unidadeId: UNIDADE, validTo: VALID_TO, motivo: MOTIVO },
  ],
  [
    "estrutura.posicao.criar",
    { organization_id: ORG, operationId: OPERACAO_ID, unidadeId: UNIDADE, jobRoleId: CARGO, seniorityLevelId: SENIORIDADE, validFrom: VALID_FROM, motivo: MOTIVO },
  ],
  [
    "estrutura.posicao.criar (sem senioridade)",
    { organization_id: ORG, operationId: OPERACAO_ID, unidadeId: UNIDADE, jobRoleId: CARGO, seniorityLevelId: null, validFrom: VALID_FROM, motivo: MOTIVO },
  ],
  [
    "estrutura.posicao.encerrar",
    { organization_id: ORG, operationId: OPERACAO_ID, posicaoId: POSICAO, validTo: VALID_TO, expectedVersion: 2, motivo: MOTIVO },
  ],
  [
    "estrutura.colegiado.definir",
    { organization_id: ORG, operationId: OPERACAO_ID, collaboratorId: COLABORADOR, memberCollaboratorIds: [MEMBRO_A, MEMBRO_B], validFrom: VALID_FROM, motivo: MOTIVO },
  ],
  [
    "estrutura.colegiado.definir (sem membros)",
    { organization_id: ORG, operationId: OPERACAO_ID, collaboratorId: COLABORADOR, memberCollaboratorIds: [], validFrom: VALID_FROM, motivo: MOTIVO },
  ],
  [
    "estrutura.colegiado.encerrar",
    { organization_id: ORG, operationId: OPERACAO_ID, collaboratorId: COLABORADOR, validTo: VALID_TO, motivo: MOTIVO },
  ],
  // F5-08 P3 — catálogos.
  [
    "catalogo.cargo.criar",
    { organization_id: ORG, operationId: OPERACAO_ID, nome: "Cargo Novo", code: "cargo_novo", motivo: MOTIVO },
  ],
  [
    "catalogo.cargo.criar (sem code)",
    { organization_id: ORG, operationId: OPERACAO_ID, nome: "Cargo Sem Codigo", code: null, motivo: MOTIVO },
  ],
  [
    "catalogo.cargo.renomear",
    { organization_id: ORG, operationId: OPERACAO_ID, jobRoleId: CARGO, nome: "Cargo Renomeado", expectedVersion: 0, motivo: MOTIVO },
  ],
  [
    "catalogo.cargo.status.alterar",
    { organization_id: ORG, operationId: OPERACAO_ID, jobRoleId: CARGO, status: "disabled", expectedVersion: 1, motivo: MOTIVO },
  ],
  [
    "catalogo.senioridade.criar",
    { organization_id: ORG, operationId: OPERACAO_ID, nome: "Senioridade Nova", motivo: MOTIVO },
  ],
  [
    "catalogo.senioridade.renomear",
    { organization_id: ORG, operationId: OPERACAO_ID, seniorityLevelId: SENIORIDADE, nome: "Senioridade Renomeada", expectedVersion: 0, motivo: MOTIVO },
  ],
  [
    "catalogo.senioridade.status.alterar",
    { organization_id: ORG, operationId: OPERACAO_ID, seniorityLevelId: SENIORIDADE, status: "active", expectedVersion: 1, motivo: MOTIVO },
  ],
  ["colaborador.historico.listar", { organization_id: ORG, collaborator_id: COLABORADOR }],
  [
    "colaborador.catalogo.bootstrap",
    {
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      catalogo: {
        job_roles: [{ code: "gerente", name: "Gerente" }],
        seniority_levels: ["Júnior", "Pleno"],
      },
    },
  ],
];

/** Operação → corpo válido (para derivar casos mutantes). */
function corpoValido(operacao: OperacaoColaborador): Corpo {
  const caso = CASOS_VALIDOS.find(([nome]) => nome === operacao || nome.startsWith(`${operacao} `));
  if (!caso) throw new Error(`sem caso válido para ${operacao}`);
  return { operacao, ...caso[1] };
}

/** Mutações: TODAS exigem `operation_id` (idempotência §13.5). */
const MUTACOES: readonly OperacaoColaborador[] = OPERACOES_COLABORADOR.filter(
  (operacao) =>
    operacao !== "collaborator.listar" &&
    operacao !== "collaborator.obter" &&
    operacao !== "colaborador.historico.listar"
);

/** Operações que exigem `expected_version` (linha existente §13.1). */
const COM_VERSAO: readonly OperacaoColaborador[] = [
  "collaborator.editar",
  "collaborator.identificador.definir",
  "collaborator.status.alterar",
  // F5-08 P3
  "estrutura.unidade.renomear",
  "estrutura.unidade.encerrar",
  "estrutura.posicao.encerrar",
  "catalogo.cargo.renomear",
  "catalogo.cargo.status.alterar",
  "catalogo.senioridade.renomear",
  "catalogo.senioridade.status.alterar",
];

/** Operações que exigem `motivo` (trim, não vazio). */
const COM_MOTIVO: readonly OperacaoColaborador[] = OPERACOES_COLABORADOR.filter((operacao) =>
  corpoValido(operacao).motivo !== undefined
);

/** Campos que tentam PROVAR autoridade — nunca aceitos no corpo. */
const CAMPOS_PROIBIDOS = [
  "capability",
  "role",
  "scope",
  "actor_user_profile_id",
  "actor_id",
  "user_profile_id",
  "ator",
] as const;

function validar(corpo: Corpo) {
  return validarEntradaColaborador(corpo);
}

function mensagem(corpo: Corpo): string {
  const resultado = validar(corpo);
  return resultado.ok ? "" : resultado.message;
}

describe("F5-07 contrato.ts — payloads válidos das 15 operações", () => {
  it.each(CASOS_VALIDOS)("aceita o payload válido de %s", (nome, corpo) => {
    const resultado = validar({ operacao: nome.split(" ")[0], ...corpo });

    expect(resultado.ok, JSON.stringify(resultado)).toBe(true);
  });

  it("as 30 operações (F5-07 + F5-08 P3) estão cobertas e todas validam", () => {
    const cobertas = new Set(
      CASOS_VALIDOS.map(([nome]) => nome.split(" ")[0] as OperacaoColaborador)
    );
    expect(cobertas.size).toBe(30);
    expect([...cobertas].sort()).toEqual([...OPERACOES_COLABORADOR].sort());
  });

  it("normaliza texto (trim), matrícula numérica (texto) e código de catálogo (maiúsculas)", () => {
    const criacao = validar(corpoValido("collaborator.criar"));
    expect(criacao.ok).toBe(true);
    if (!criacao.ok) return;
    expect(criacao.entrada).toMatchObject({
      organization_id: ORG,
      full_name: "Maria Silva",
      email: "maria@example.invalid",
      matricula: "1234",
      operation_id: OPERACAO_ID,
      status_inicial: "leave",
      admission_date: "2024-02-01",
    });

    const bootstrap = validar(corpoValido("colaborador.catalogo.bootstrap"));
    expect(bootstrap.ok).toBe(true);
    if (!bootstrap.ok) return;
    expect(bootstrap.entrada).toMatchObject({
      catalogo: {
        job_roles: [{ code: "GERENTE", name: "Gerente" }],
        seniority_levels: ["Júnior", "Pleno"],
      },
    });
  });

  it("conserva a matrícula como INTENÇÃO em texto, inclusive com zeros à esquerda", () => {
    const resultado = validar({ operacao: "collaborator.obter", organization_id: ORG, matricula: 7 });
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada).toMatchObject({ matricula: "7", organization_id: ORG });

    const zeros = validar({
      operacao: "collaborator.obter",
      organization_id: ORG,
      matricula: "007",
    });
    expect(zeros.ok).toBe(true);
    if (!zeros.ok) return;
    expect(zeros.entrada).toMatchObject({ matricula: "007" });
  });

  it("`operation_id` e `expected_version` são aceitos em operações que não os exigem sem virar intenção", () => {
    const resultado = validar({
      operacao: "colaborador.ocupacao.definir",
      organization_id: ORG,
      operation_id: OPERACAO_ID,
      collaborator_id: COLABORADOR,
      position_id: POSICAO,
      vigencia: VIGENCIA,
      motivo: MOTIVO,
      expected_version: 5,
    });
    expect(resultado.ok).toBe(true);
  });
});

describe("F5-07 contrato.ts — corpo, operação e organização (fail-closed)", () => {
  it.each([
    ["null", null],
    ["array", []],
    ["string", "colaborador"],
    ["número", 42],
    ["booleana", true],
  ])("recusa corpo inválido (%s) com INVALID_INPUT", (_nome, corpo) => {
    const resultado = validarEntradaColaborador(corpo);
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.code).toBe("INVALID_INPUT");
    expect(resultado.message).toBe("Corpo da requisição inválido.");
  });

  it.each([["desconhecida", "collaborator.apagar"], ["ausente", undefined], ["vazia", ""]])(
    "recusa operação %s",
    (_nome, operacao) => {
      const resultado = validar({ operacao, organization_id: ORG });
      expect(resultado.ok).toBe(false);
      if (resultado.ok) return;
      expect(resultado.code).toBe("INVALID_INPUT");
    }
  );

  it.each([
    ["ausente", undefined],
    ["vazia", ""],
    ["não-UUID", "organizacao-1"],
    ["número", 42],
    ["nula", null],
  ])("recusa organization_id %s", (_nome, organization_id) => {
    const resultado = validar({ operacao: "collaborator.listar", organization_id });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.code).toBe("INVALID_INPUT");
    expect(resultado.message).toBe("organization_id inválido.");
  });

  it("aceita organization_id de OUTRA organização: é INTENÇÃO (a Edge revalida)", () => {
    const resultado = validar({
      operacao: "collaborator.listar",
      organization_id: OUTRA_ORG,
    });
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada).toMatchObject({ organization_id: OUTRA_ORG });
  });

  it("IGNORA o `alvo` enviado pela tela (nunca é prova de alvo autorizável)", () => {
    const criacao = validar({
      ...corpoValido("collaborator.criar"),
      alvo: { type: "collaborator", id: COLABORADOR },
    });
    expect(criacao.ok).toBe(true);
    if (!criacao.ok) return;
    expect(criacao.entrada).toMatchObject({ alvo: { type: "collaborator", id: ID_NEUTRO } });

    const porMatricula = validar({
      operacao: "collaborator.obter",
      organization_id: ORG,
      matricula: "1234",
      alvo: { type: "collaborator", id: COLABORADOR },
    });
    expect(porMatricula.ok).toBe(true);
    if (!porMatricula.ok) return;
    expect(porMatricula.entrada).toMatchObject({ alvo: { type: "collaborator", id: ID_NEUTRO } });
  });
});

describe("F5-07 contrato.ts — identidade, capability e escopo NUNCA vêm do corpo (§8.2)", () => {
  it.each(CAMPOS_PROIBIDOS)("recusa o campo proibido `%s`", (campo) => {
    const resultado = validar({ ...corpoValido("collaborator.criar"), [campo]: "x" });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.code).toBe("INVALID_INPUT");
    expect(resultado.message).toContain("capability");
  });

  it("recusa os campos proibidos mesmo em operação de LEITURA", () => {
    for (const campo of CAMPOS_PROIBIDOS) {
      const resultado = validar({ ...corpoValido("collaborator.listar"), [campo]: "x" });
      expect(resultado.ok, campo).toBe(false);
    }
  });

  it("recusa `capability` declarada como ADMINISTRATIVA (D19 é server-side)", () => {
    const resultado = validar({
      ...corpoValido("colaborador.catalogo.bootstrap"),
      capability: "org.catalog.manage",
    });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.code).toBe("INVALID_INPUT");
  });
});

describe("F5-07 contrato.ts — idempotência e concorrência (§13)", () => {
  it.each(MUTACOES)("exige operation_id na mutação %s", (operacao) => {
    const corpo = corpoValido(operacao);
    delete corpo.operation_id;
    delete corpo.operationId;

    const resultado = validar(corpo);
    expect(resultado.ok, operacao).toBe(false);
    if (resultado.ok) return;
    expect(resultado.code).toBe("INVALID_INPUT");
    expect(resultado.message).toBe("operation_id obrigatório.");
  });

  it.each([["não-UUID", "op-1"], ["vazio", ""], ["número", 7]])(
    "recusa operation_id %s",
    (_nome, operation_id) => {
      const resultado = validar({ ...corpoValido("collaborator.criar"), operation_id });
      expect(resultado.ok).toBe(false);
      if (resultado.ok) return;
      expect(resultado.message).toBe("operation_id inválido.");
    }
  );

  it("NÃO exige operation_id nas operações de leitura", () => {
    for (const operacao of ["collaborator.listar", "collaborator.obter", "colaborador.historico.listar"] as const) {
      const resultado = validar(corpoValido(operacao));
      expect(resultado.ok, operacao).toBe(true);
    }
  });

  it.each(COM_VERSAO)("exige expected_version em %s", (operacao) => {
    const corpo = corpoValido(operacao);
    delete corpo.expected_version;
    delete corpo.expectedVersion;

    const resultado = validar(corpo);
    expect(resultado.ok, operacao).toBe(false);
    if (resultado.ok) return;
    expect(resultado.code).toBe("INVALID_INPUT");
    expect(resultado.message).toBe("expected_version obrigatório.");
  });

  it.each(COM_VERSAO)("recusa expected_version nula em %s (null não é versão)", (operacao) => {
    const resultado = validar({
      ...corpoValido(operacao),
      expected_version: null,
      expectedVersion: null,
    });
    expect(resultado.ok, operacao).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe("expected_version obrigatório.");
  });

  it.each([
    ["fracionária", 1.5],
    ["negativa", -1],
    ["texto", "3"],
    ["booleana", true],
  ])("recusa expected_version %s", (_nome, expected_version) => {
    const resultado = validar({ ...corpoValido("collaborator.editar"), expected_version });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe("expected_version inválido.");
  });

  it("aceita expected_version 0 (primeira versão é válida para a forma)", () => {
    const resultado = validar({ ...corpoValido("collaborator.editar"), expected_version: 0 });
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada).toMatchObject({ expected_version: 0 });
  });

  it("não exige expected_version nas operações estruturais (contrato §8.1)", () => {
    for (const operacao of [
      "colaborador.ocupacao.definir",
      "colaborador.ocupacao.encerrar",
      "estrutura.reporting.definir",
      "estrutura.reporting.encerrar",
      "estrutura.responsabilidade.definir",
      "estrutura.responsabilidade.encerrar",
      "estrutura.sucessao.registrar",
      "colaborador.catalogo.bootstrap",
    ] as const) {
      expect(validar(corpoValido(operacao)).ok, operacao).toBe(true);
    }
  });
});

describe("F5-07 contrato.ts — motivo, domínios fechados e vigência", () => {
  it.each(COM_MOTIVO)("exige motivo não vazio em %s", (operacao) => {
    const semMotivo = corpoValido(operacao);
    delete semMotivo.motivo;
    expect(validar(semMotivo).ok, `${operacao} sem motivo`).toBe(false);

    const emBranco = validar({ ...corpoValido(operacao), motivo: "   " });
    expect(emBranco.ok, `${operacao} com motivo em branco`).toBe(false);
    if (emBranco.ok) return;
    expect(emBranco.message).toBe("motivo obrigatório.");
  });

  it("normaliza o motivo com trim", () => {
    const resultado = validar({ ...corpoValido("estrutura.reporting.encerrar"), motivo: "  fim  " });
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada).toMatchObject({ motivo: "fim" });
  });

  it.each([["fora do domínio", "inativo"], ["domínio vizinho", "ACTIVE"], ["vazio", ""]])(
    "recusa novo_status %s",
    (_nome, novo_status) => {
      const resultado = validar({ ...corpoValido("collaborator.status.alterar"), novo_status });
      expect(resultado.ok).toBe(false);
      if (resultado.ok) return;
      expect(resultado.message).toBe("novo_status inválido.");
    }
  );

  it.each([["inactive (fora do domínio inicial)", "inactive"], ["ACTIVE", "ACTIVE"]])(
    "recusa status_inicial %s na criação",
    (_nome, status_inicial) => {
      const resultado = validar({ ...corpoValido("collaborator.criar"), status_inicial });
      expect(resultado.ok).toBe(false);
      if (resultado.ok) return;
      expect(resultado.message).toBe("status_inicial inválido.");
    }
  );

  it.each([
    ["vazia", ""],
    ["em branco", "   "],
    ["texto", "abc"],
    ["zero", 0],
    ["negativa", -1],
    ["fracionária", 1.5],
  ])("recusa matrícula %s na criação", (_nome, matricula) => {
    const resultado = validar({ ...corpoValido("collaborator.criar"), matricula });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe("matricula inválida.");
  });

  it.each([
    ["data_referencia", { data_referencia: "31/01/2026" }],
    ["vigencia", { vigencia: "amanhã" }],
    ["motivo vazio na sucessão", { motivo: "  " }],
  ])("recusa %s inválida", (_nome, extra) => {
    const base =
      "vigencia" in extra
        ? corpoValido("estrutura.reporting.encerrar")
        : "motivo" in extra
          ? corpoValido("estrutura.sucessao.registrar")
          : corpoValido("collaborator.listar");
    const resultado = validar({ ...base, ...extra });
    expect(resultado.ok).toBe(false);
  });

  it("recusa vigencia ausente nas operações com vigência", () => {
    const corpo = corpoValido("colaborador.ocupacao.encerrar");
    delete corpo.vigencia;
    const resultado = validar(corpo);
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe("vigencia inválida.");
  });

  it.each([["ciclo fora do domínio", "CICLO_ATUAL"], ["vazio", ""]])(
    "recusa cycle_scope %s",
    (_nome, cycle_scope) => {
      const resultado = validar({ ...corpoValido("collaborator.status.alterar"), cycle_scope });
      expect(resultado.ok).toBe(false);
      if (resultado.ok) return;
      expect(resultado.message).toBe("cycle_scope inválido.");
    }
  );

  it("recusa reference_cycle_id não-UUID", () => {
    const resultado = validar({
      ...corpoValido("collaborator.status.alterar"),
      reference_cycle_id: "ciclo-1",
    });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe("reference_cycle_id inválido.");
  });

  it("recusa auto-reporting (subordinado == gestor)", () => {
    const resultado = validar({
      ...corpoValido("estrutura.reporting.definir"),
      manager_position_id: POSICAO,
    });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe("Auto-reporting é inválido.");
  });

  it.each([
    ["position_id inválido", { position_id: "x" }],
    ["substituto inválido", { substitute_collaborator_id: "x" }],
    ["tipo fora do domínio", { responsibility_type: "temporaria" }],
  ])("recusa responsabilidade com %s", (_nome, extra) => {
    const resultado = validar({
      ...corpoValido("estrutura.responsabilidade.definir"),
      ...extra,
    });
    expect(resultado.ok).toBe(false);
  });

  it.each([
    ["vazio", []],
    ["item não-UUID", ["x"]],
    ["duplicado inválido", [RESPONSABILIDADE, "y"]],
  ])("recusa responsibility_ids %s", (_nome, responsibility_ids) => {
    const resultado = validar({
      ...corpoValido("estrutura.sucessao.registrar"),
      responsibility_ids,
    });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe("responsibility_ids inválido.");
  });

  it("exige succession_date válida", () => {
    const semData = corpoValido("estrutura.sucessao.registrar");
    delete semData.succession_date;
    expect(validar(semData).ok).toBe(false);

    const invalida = validar({
      ...corpoValido("estrutura.sucessao.registrar"),
      succession_date: "01/04/2026",
    });
    expect(invalida.ok).toBe(false);
  });

  it("recusa e-mail inválido na criação e edição", () => {
    for (const email of ["sem-arroba", "@example.invalid", "   "]) {
      expect(validar({ ...corpoValido("collaborator.criar"), email }).ok, email).toBe(false);
      expect(validar({ ...corpoValido("collaborator.editar"), email }).ok, email).toBe(false);
    }
  });

  it("recusa edição sem nenhum dado de pessoa (a operação não é 'nada a fazer')", () => {
    const corpo = corpoValido("collaborator.editar");
    delete corpo.email;
    const resultado = validar(corpo);
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toContain("full_name");
  });
});

describe("F5-07 contrato.ts — leituras, filtros e catálogo", () => {
  it("recusa `collaborator.obter` sem alvo ou com alvo duplo", () => {
    const semAlvo = validar({ operacao: "collaborator.obter", organization_id: ORG });
    expect(semAlvo.ok).toBe(false);
    if (semAlvo.ok) return;
    expect(semAlvo.message).toBe("collaborator_id ou matricula é obrigatório.");

    const duplo = validar({
      operacao: "collaborator.obter",
      organization_id: ORG,
      collaborator_id: COLABORADOR,
      matricula: "1234",
    });
    expect(duplo.ok).toBe(false);
    if (duplo.ok) return;
    expect(duplo.message).toBe("Informe collaborator_id OU matricula, nunca os dois.");
  });

  it("recusa collaborator_id inválido nas operações com alvo", () => {
    for (const operacao of [
      "collaborator.obter",
      "collaborator.editar",
      "collaborator.identificador.definir",
      "collaborator.status.alterar",
      "colaborador.historico.listar",
    ] as const) {
      const resultado = validar({ ...corpoValido(operacao), collaborator_id: "colaborador-1" });
      expect(resultado.ok, operacao).toBe(false);
      if (resultado.ok) return;
      expect(resultado.message).toBe("collaborator_id inválido.");
    }
  });

  it.each([
    ["chave desconhecida", { status: "active", cargo: "GERENTE" }],
    ["unit_id não-UUID", { unit_id: "unidade-1" }],
    ["status vazio", { status: "   " }],
    ["busca vazia", { busca: "" }],
    ["não-objeto", "active"],
  ])("recusa filtros com %s", (_nome, filtros) => {
    const resultado = validar({ operacao: "collaborator.listar", organization_id: ORG, filtros });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe("filtros inválidos.");
  });

  it("aceita filtros válidos e descarta os nulos", () => {
    const resultado = validar({
      operacao: "collaborator.listar",
      organization_id: ORG,
      filtros: { busca: "silva", status: null, unit_id: undefined },
    });
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada).toMatchObject({ filtros: { busca: "silva" } });
  });

  it("`colaborador.historico.listar` aceita data_referencia e reference_cycle_id sem exigi-los", () => {
    const resultado = validar({
      operacao: "colaborador.historico.listar",
      organization_id: ORG,
      collaborator_id: COLABORADOR,
      data_referencia: "2026-01-31",
      reference_cycle_id: CICLO,
    });
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada).toMatchObject({
      data_referencia: "2026-01-31",
      reference_cycle_id: CICLO,
    });
  });

  it.each([
    ["chave extra", { job_roles: [{ code: "GERENTE", name: "Gerente" }], seniority_levels: ["Pleno"], positions: [] }],
    ["job_roles vazio", { job_roles: [], seniority_levels: ["Pleno"] }],
    ["sem seniority_levels", { job_roles: [{ code: "GERENTE", name: "Gerente" }] }],
    ["senioridade em branco", { job_roles: [{ code: "GERENTE", name: "Gerente" }], seniority_levels: ["  "] }],
    ["código inválido", { job_roles: [{ code: "G", name: "Gerente" }], seniority_levels: ["Pleno"] }],
    ["chave extra no job_role", { job_roles: [{ code: "GERENTE", name: "Gerente", level: 1 }], seniority_levels: ["Pleno"] }],
  ])("recusa catálogo com %s", (_nome, catalogo) => {
    const resultado = validar({ ...corpoValido("colaborador.catalogo.bootstrap"), catalogo });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe("catalogo inválido.");
  });

  it("o catálogo do bootstrap NUNCA cria estrutura (D16): só job_roles e seniority_levels", () => {
    const resultado = validar(corpoValido("colaborador.catalogo.bootstrap"));
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(Object.keys(resultado.entrada)).toEqual(["organization_id", "operation_id", "catalogo"]);
  });
});

describe("F5-07 contrato.ts — guardas de vocabulário", () => {
  it("`ehUuid` aceita apenas UUID e o alvo neutro é um UUID válido", () => {
    expect(ehUuid(COLABORADOR)).toBe(true);
    expect(ehUuid(ID_NEUTRO)).toBe(true);
    expect(ehUuid("  " + COLABORADOR + "  ")).toBe(true);
    expect(ehUuid("")).toBe(false);
    expect(ehUuid("nao-uuid")).toBe(false);
    expect(ehUuid(123)).toBe(false);
  });

  it("`ehOperacaoColaborador` é fail-closed para código desconhecido", () => {
    expect(ehOperacaoColaborador("collaborator.listar")).toBe(true);
    expect(ehOperacaoColaborador("collaborator.apagar")).toBe(false);
    expect(ehOperacaoColaborador("collaborator.manage")).toBe(false);
    expect(ehOperacaoColaborador(undefined)).toBe(false);
  });

  it("todas as mensagens de recusa são INVALID_INPUT (nunca INTERNAL/FORBIDDEN)", () => {
    const corposInvalidos: Corpo[] = [
      { operacao: "collaborator.listar", organization_id: "x" },
      { operacao: "collaborator.criar", organization_id: ORG },
      { operacao: "collaborator.status.alterar", organization_id: ORG, novo_status: "x" },
    ];
    for (const corpo of corposInvalidos) {
      const resultado = validar(corpo);
      expect(resultado.ok).toBe(false);
      if (resultado.ok) return;
      expect(resultado.code).toBe("INVALID_INPUT");
      expect(mensagem(corpo)).not.toContain("F5_07");
    }
  });
});

describe("F5-08 P3 — contrato.ts: nuláveis, arrays e domínios das operações novas", () => {
  it("aceita parentUnitId null (RAIZ) e também ausente", () => {
    const explicito = validar({ ...corpoValido("estrutura.unidade.parent.definir") });
    expect(explicito.ok).toBe(true);

    const raiz = validar({
      ...corpoValido("estrutura.unidade.parent.definir"),
      parentUnitId: null,
    });
    expect(raiz.ok).toBe(true);
    if (!raiz.ok) return;
    expect(raiz.entrada).toMatchObject({ parentUnitId: null });

    const ausente = corpoValido("estrutura.unidade.parent.definir");
    delete ausente.parentUnitId;
    const semCampo = validar(ausente);
    expect(semCampo.ok).toBe(true);
    if (!semCampo.ok) return;
    expect(semCampo.entrada).toMatchObject({ parentUnitId: null });
  });

  it("recusa parentUnitId que não é UUID nem null", () => {
    const resultado = validar({
      ...corpoValido("estrutura.unidade.parent.definir"),
      parentUnitId: "unidade-1",
    });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe("parentUnitId inválido.");
  });

  it("aceita seniorityLevelId null/ausente e recusa seniorityLevelId inválida", () => {
    const semSenioridade = corpoValido("estrutura.posicao.criar");
    delete semSenioridade.seniorityLevelId;
    const ausente = validar(semSenioridade);
    expect(ausente.ok).toBe(true);
    if (!ausente.ok) return;
    expect(ausente.entrada).toMatchObject({ seniorityLevelId: null });

    const invalida = validar({
      ...corpoValido("estrutura.posicao.criar"),
      seniorityLevelId: 42,
    });
    expect(invalida.ok).toBe(false);
    if (invalida.ok) return;
    expect(invalida.message).toBe("seniorityLevelId inválido.");
  });

  it("aceita lista VAZIA de membros (0..N = 'sem colegiado' explícito)", () => {
    const resultado = validar({
      ...corpoValido("estrutura.colegiado.definir"),
      memberCollaboratorIds: [],
    });
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada).toMatchObject({ memberCollaboratorIds: [] });
  });

  it.each([
    ["não-array", "membro"],
    ["com item inválido", [MEMBRO_A, "membro-1"]],
    ["com null", [MEMBRO_A, null]],
  ])("recusa memberCollaboratorIds %s", (_nome, memberCollaboratorIds) => {
    const resultado = validar({
      ...corpoValido("estrutura.colegiado.definir"),
      memberCollaboratorIds,
    });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe("memberCollaboratorIds inválido.");
  });

  it("NÃO impõe teto de membros: 250 UUIDs válidos continuam válidos (0..N)", () => {
    const muitos = Array.from(
      { length: 250 },
      (_, indice) => "00000000-0000-4000-8000-" + String(indice).padStart(12, "0")
    );
    const resultado = validar({
      ...corpoValido("estrutura.colegiado.definir"),
      memberCollaboratorIds: muitos,
    });

    expect(resultado.ok, JSON.stringify(resultado)).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.entrada).toMatchObject({ memberCollaboratorIds: muitos });
  });

  it("normaliza `code` do cargo para caixa alta e aceita ausência", () => {
    const minusculo = validar({
      ...corpoValido("catalogo.cargo.criar"),
      code: "  cargo_novo  ",
    });
    expect(minusculo.ok).toBe(true);
    if (!minusculo.ok) return;
    expect(minusculo.entrada).toMatchObject({ code: "CARGO_NOVO" });

    const semCode = corpoValido("catalogo.cargo.criar");
    delete semCode.code;
    const ausente = validar(semCode);
    expect(ausente.ok).toBe(true);
    if (!ausente.ok) return;
    expect(ausente.entrada).toMatchObject({ code: null });
  });

  it.each([
    ["vazio", ""],
    ["em branco", "   "],
    ["longo demais", "A".repeat(41)],
    ["número", 7],
  ])("recusa code %s", (_nome, code) => {
    const resultado = validar({ ...corpoValido("catalogo.cargo.criar"), code });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe("code inválido.");
  });

  it.each([
    ["fora do domínio", "inativo"],
    ["caixa alta", "ACTIVE"],
    ["vazio", ""],
  ])("recusa status %s nos catálogos", (_nome, status) => {
    for (const operacao of [
      "catalogo.cargo.status.alterar",
      "catalogo.senioridade.status.alterar",
    ] as const) {
      const resultado = validar({ ...corpoValido(operacao), status });
      expect(resultado.ok, operacao).toBe(false);
      if (resultado.ok) return;
      expect(resultado.message).toBe("status inválido.");
    }
  });

  it.each([
    ["estrutura.unidade.criar", "validFrom"],
    ["estrutura.unidade.encerrar", "validTo"],
    ["estrutura.unidade.parent.definir", "validFrom"],
    ["estrutura.unidade.parent.encerrar", "validTo"],
    ["estrutura.posicao.criar", "validFrom"],
    ["estrutura.posicao.encerrar", "validTo"],
    ["estrutura.colegiado.definir", "validFrom"],
    ["estrutura.colegiado.encerrar", "validTo"],
  ] as const)("recusa %s com data inválida em %s", (operacao, campo) => {
    const resultado = validar({
      ...corpoValido(operacao),
      [campo]: "01/04/2026",
    });
    expect(resultado.ok, operacao).toBe(false);
    if (resultado.ok) return;
    expect(resultado.message).toBe(`${campo} inválido.`);
  });

  it.each([
    "estrutura.unidade.criar",
    "estrutura.unidade.renomear",
    "estrutura.unidade.encerrar",
    "estrutura.posicao.criar",
    "estrutura.posicao.encerrar",
    "estrutura.colegiado.definir",
    "catalogo.cargo.criar",
    "catalogo.senioridade.criar",
    "catalogo.senioridade.status.alterar",
  ] as const)("recusa UUID inválido em %s", (operacao) => {
    const corpo = corpoValido(operacao);
    for (const campo of [
      "unidadeId",
      "posicaoId",
      "jobRoleId",
      "seniorityLevelId",
      "collaboratorId",
    ]) {
      if (!(campo in corpo)) continue;
      const invalido = validar({ ...corpo, [campo]: "nao-e-uuid" });
      expect(invalido.ok, `${operacao}.${campo}`).toBe(false);
    }
  });

  it("aceita `operationId` do P3 e exige presença em toda mutação nova", () => {
    const valido = validar(corpoValido("catalogo.senioridade.criar"));
    expect(valido.ok).toBe(true);
    if (!valido.ok) return;
    expect(valido.entrada).toMatchObject({ operationId: OPERACAO_ID });

    const invalido = validar({
      ...corpoValido("catalogo.senioridade.criar"),
      operationId: "op-1",
    });
    expect(invalido.ok).toBe(false);
    if (invalido.ok) return;
    expect(invalido.message).toBe("operation_id inválido.");
  });
});
