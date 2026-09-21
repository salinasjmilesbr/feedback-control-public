/**
 * #327/P2B — LEITURA POR VIEW do repositório do cliente.
 *
 * O cliente deixou de ler 10 tabelas: cada escopo lê UMA view soberana
 * (`estrutura_administrativa` ou `estrutura_pessoal`) e a segurança continua
 * INTEIRA no servidor. Prova:
 * - escopo ausente/desconhecido => view ADMINISTRATIVA (nunca amplia);
 * - escopo `pessoal` => view PESSOAL;
 * - ZERO linha => `FORBIDDEN` (sem autorização server-side; nunca "vazio");
 * - erro 42501/PGRST301 => `FORBIDDEN`; outro erro => `INTERNAL`;
 * - sem sessão => `NOT_AUTHORIZED`; sem organização => `FORBIDDEN`;
 * - o payload jsonb é mapeado para a fotografia soberana, com listas vazias
 *   quando a seção está ausente (defensivo), sem inventar dado (I7).
 */

import { describe, expect, it } from "vitest";
import { criarLeituraEstrutura } from "./repositorioEstruturaSoberana";

const ORG = "11111111-1111-4111-8111-111111111111";

const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const PERIODO = "99999999-9999-4999-8999-999999999999";
const POSICAO = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const POSICAO_CHEFE = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const REPORTING = "77777777-7777-4777-8777-777777777777";
const OCUPACAO = "88888888-8888-4888-8888-888888888888";
const COLABORADOR = "22222222-2222-4222-8222-222222222222";
const MEMBRO = "33333333-3333-4333-8333-333333333333";
const COLEGIADO = "55555555-5555-4555-8555-555555555555";
const CARGO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const SENIORIDADE = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const INICIO = "2026-03-01T00:00:00Z";

interface Captura {
  view?: string;
  colunas?: string;
  filtro?: unknown;
}

interface RespostaFalsa {
  readonly data: unknown;
  readonly error: unknown;
}

/** Cliente PostgREST falso: registra view/colunas/filtro e devolve a resposta. */
function clienteFalso(resposta: RespostaFalsa, captura: Captura, sessao = true) {
  const cliente = {
    auth: {
      getSession: async () => ({
        data: { session: sessao ? { access_token: "token-ficticio" } : null },
      }),
    },
    from(view: string) {
      captura.view = view;
      return {
        select(colunas: string) {
          captura.colunas = colunas;
          return {
            eq(_coluna: string, valor: unknown) {
              captura.filtro = valor;
              return { maybeSingle: async () => resposta };
            },
          };
        },
      };
    },
  };
  return cliente as never;
}

const PAYLOAD = {
  organization_id: ORG,
  unidades: [
    { id: UNIDADE, name: "Unidade Fictícia", valid_from: INICIO, valid_to: null, version: 3 },
  ],
  periodos_parent: [
    {
      id: PERIODO,
      unit_id: UNIDADE,
      parent_unit_id: null,
      valid_from: INICIO,
      valid_to: null,
      version: 1,
    },
  ],
  posicoes: [
    {
      id: POSICAO,
      unit_id: UNIDADE,
      job_role_id: CARGO,
      seniority_level_id: SENIORIDADE,
      valid_from: INICIO,
      valid_to: null,
      version: 2,
    },
  ],
  reporting_lines: [
    {
      id: REPORTING,
      subordinate_position_id: POSICAO,
      manager_position_id: POSICAO_CHEFE,
      reason: "motivo fictício",
      valid_from: INICIO,
      valid_to: null,
      version: 1,
    },
  ],
  ocupacoes: [
    {
      id: OCUPACAO,
      collaborator_id: COLABORADOR,
      organizational_position_id: POSICAO,
      valid_from: INICIO,
      valid_to: null,
      version: 1,
    },
  ],
  colegiados: [
    {
      id: COLEGIADO,
      collaborator_id: COLABORADOR,
      valid_from: INICIO,
      valid_to: null,
      version: 1,
    },
  ],
  membros_colegiado: [
    { configuration_id: COLEGIADO, member_collaborator_id: MEMBRO },
    { configuration_id: COLEGIADO, member_collaborator_id: COLABORADOR },
  ],
  colaboradores: [{ id: COLABORADOR, full_name: "Pessoa Fictícia" }],
  cargos: [{ id: CARGO, code: "FICT", name: "Cargo Fictício", status: "active", version: 1 }],
  senioridades: [{ id: SENIORIDADE, name: "Senioridade Fictícia", status: "active", version: 1 }],
};

describe("#327/P2B — repositório por view", () => {
  it("escopo ausente lê a view ADMINISTRATIVA com o filtro do tenant", async () => {
    const captura: Captura = {};
    const leitura = criarLeituraEstrutura(clienteFalso({ data: PAYLOAD, error: null }, captura));

    const resultado = await leitura.ler({ organizationId: ORG });

    expect(resultado.ok).toBe(true);
    expect(captura.view).toBe("estrutura_administrativa");
    expect(captura.filtro).toBe(ORG);
    expect(captura.colunas).toContain("unidades");
    expect(captura.colunas).toContain("membros_colegiado");
    expect(captura.colunas).toContain("senioridades");
  });

  it("escopo pessoal lê a view PESSOAL", async () => {
    const captura: Captura = {};
    const leitura = criarLeituraEstrutura(clienteFalso({ data: PAYLOAD, error: null }, captura));

    const resultado = await leitura.ler({ organizationId: ORG, escopo: "pessoal" });

    expect(resultado.ok).toBe(true);
    expect(captura.view).toBe("estrutura_pessoal");
  });

  it("mapeia o payload jsonb para a fotografia soberana", async () => {
    const leitura = criarLeituraEstrutura(clienteFalso({ data: PAYLOAD, error: null }, {}));

    const resultado = await leitura.ler({ organizationId: ORG });
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;

    expect(resultado.data.unidades).toEqual([
      {
        unitId: UNIDADE,
        nome: "Unidade Fictícia",
        validFrom: INICIO,
        validTo: null,
        version: 3,
      },
    ]);
    expect(resultado.data.periodosParent[0]).toMatchObject({
      periodoId: PERIODO,
      unitId: UNIDADE,
      parentUnitId: null,
    });
    expect(resultado.data.posicoes[0]).toMatchObject({
      posicaoId: POSICAO,
      unitId: UNIDADE,
      jobRoleId: CARGO,
      seniorityLevelId: SENIORIDADE,
    });
    expect(resultado.data.reportingLines[0]).toMatchObject({
      reportingLineId: REPORTING,
      subordinatePositionId: POSICAO,
      managerPositionId: POSICAO_CHEFE,
      motivo: "motivo fictício",
    });
    expect(resultado.data.ocupacoes[0]).toMatchObject({
      ocupacaoId: OCUPACAO,
      collaboratorId: COLABORADOR,
      posicaoId: POSICAO,
    });
    expect(resultado.data.colegiados[0]).toMatchObject({
      colegiadoId: COLEGIADO,
      collaboratorId: COLABORADOR,
      membroIds: [MEMBRO, COLABORADOR],
    });
    expect(resultado.data.colaboradores).toEqual([
      { collaboratorId: COLABORADOR, nome: "Pessoa Fictícia" },
    ]);
    expect(resultado.data.cargos).toEqual([
      {
        jobRoleId: CARGO,
        code: "FICT",
        nome: "Cargo Fictício",
        status: "active",
        version: 1,
      },
    ]);
    expect(resultado.data.senioridades).toEqual([
      {
        seniorityLevelId: SENIORIDADE,
        nome: "Senioridade Fictícia",
        status: "active",
        version: 1,
      },
    ]);
  });

  it("seções ausentes viram listas vazias (defensivo, sem inventar dado)", async () => {
    const leitura = criarLeituraEstrutura(
      clienteFalso({ data: { organization_id: ORG }, error: null }, {})
    );

    const resultado = await leitura.ler({ organizationId: ORG });
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.data.unidades).toEqual([]);
    expect(resultado.data.colegiados).toEqual([]);
    expect(resultado.data.colaboradores).toEqual([]);
    expect(resultado.data.cargos).toEqual([]);
  });

  it("ZERO linha da view => FORBIDDEN (autoridade é o servidor)", async () => {
    const leitura = criarLeituraEstrutura(clienteFalso({ data: null, error: null }, {}));

    const resultado = await leitura.ler({ organizationId: ORG });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("FORBIDDEN");
  });

  it("erro de privilégio => FORBIDDEN; erro inesperado => INTERNAL", async () => {
    const negado = criarLeituraEstrutura(
      clienteFalso({ data: null, error: { code: "42501", message: "permission denied" } }, {})
    );
    const resultadoNegado = await negado.ler({ organizationId: ORG });
    expect(resultadoNegado.ok).toBe(false);
    if (!resultadoNegado.ok) expect(resultadoNegado.error.code).toBe("FORBIDDEN");

    const semJwt = criarLeituraEstrutura(
      clienteFalso({ data: null, error: { code: "PGRST301", message: "JWT" } }, {})
    );
    const resultadoSemJwt = await semJwt.ler({ organizationId: ORG });
    expect(resultadoSemJwt.ok).toBe(false);
    if (!resultadoSemJwt.ok) expect(resultadoSemJwt.error.code).toBe("FORBIDDEN");

    const interno = criarLeituraEstrutura(
      clienteFalso({ data: null, error: { code: "XX000", message: "falha interna" } }, {})
    );
    const resultadoInterno = await interno.ler({ organizationId: ORG });
    expect(resultadoInterno.ok).toBe(false);
    if (!resultadoInterno.ok) expect(resultadoInterno.error.code).toBe("INTERNAL");
  });

  it("sem sessão => NOT_AUTHORIZED, sem consultar a view", async () => {
    const captura: Captura = {};
    const leitura = criarLeituraEstrutura(
      clienteFalso({ data: PAYLOAD, error: null }, captura, false)
    );

    const resultado = await leitura.ler({ organizationId: ORG });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("NOT_AUTHORIZED");
    expect(captura.view).toBeUndefined();
  });

  it("sem organização ativa => FORBIDDEN, sem consultar a view", async () => {
    const captura: Captura = {};
    const leitura = criarLeituraEstrutura(clienteFalso({ data: PAYLOAD, error: null }, captura));

    const semOrganizacao = await leitura.ler({ organizationId: null });
    expect(semOrganizacao.ok).toBe(false);
    if (!semOrganizacao.ok) expect(semOrganizacao.error.code).toBe("FORBIDDEN");
    expect(captura.view).toBeUndefined();
  });
});
