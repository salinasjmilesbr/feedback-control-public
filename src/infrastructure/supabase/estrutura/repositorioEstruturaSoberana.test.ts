/**
 * F5-08 P4 — repositório do cliente: payloads da Edge (15 operações) e LEITURA
 * SOBERANA por RLS (D16).
 *
 * Prova:
 * - cada operação envia `operacao` + `organization_id` (INTENÇÃO) e os campos
 *   públicos em camelCase (`operationId`, `expectedVersion`, vigência, `motivo`);
 * - nenhuma identidade/ator/capability/credencial é anexada no cliente;
 * - a leitura exige SESSÃO (sem sessão ⇒ `NOT_AUTHORIZED`, nunca conjunto vazio
 *   por negação) e filtra o tenant na consulta (defesa em profundidade);
 * - erro do PostgREST vira código público sem vazar mensagem do banco.
 */

import { describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  criarRepositorioColaboradoresSupabase,
  FUNCAO_COLABORADORES,
} from "../colaboradores/repositorioColaboradores";
import { criarLeituraEstrutura } from "./repositorioEstruturaSoberana";

const ORG = "11111111-1111-4111-8111-111111111111";
const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const POSICAO = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const COLABORADOR = "22222222-2222-4222-8222-222222222222";
const MEMBRO = "33333333-3333-4333-8333-333333333333";
const CARGO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const SENIORIDADE = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const OPERACAO_ID = "66666666-6666-4666-8666-666666666666";
const INICIO = "2026-03-01";
const FIM = "2026-06-30";
const MOTIVO = "reorganização aprovada";

interface Invocacao {
  readonly nome: string;
  readonly body: Record<string, unknown>;
}

function clienteEdgeFalso(resposta: {
  readonly data?: unknown;
  readonly error?: unknown;
}): { readonly cliente: SupabaseClient; readonly invocacoes: Invocacao[] } {
  const invocacoes: Invocacao[] = [];
  const cliente = {
    functions: {
      invoke: async (nome: string, opcoes: { body: Record<string, unknown> }) => {
        invocacoes.push({ nome, body: opcoes.body });
        return { data: resposta.data ?? null, error: resposta.error ?? null };
      },
    },
    auth: {
      getSession: async () => ({
        data: { session: { access_token: "token-ficticio" } },
        error: null,
      }),
    },
  } as unknown as SupabaseClient;
  return { cliente, invocacoes };
}

/** Resposta da Edge com sucesso (`resultado` cru do servidor). */
function sucesso(resultado: unknown) {
  return { data: { ok: true, operacao: "x", resultado } };
}

describe("F5-08 P4 — payload das 15 operações administrativas na Edge", () => {
  it("criarUnidade/renomear/encerrar/parent respeitam o contrato público", async () => {
    const casos: readonly {
      readonly chamar: (
        repo: ReturnType<typeof criarRepositorioColaboradoresSupabase>
      ) => Promise<unknown>;
      readonly esperado: Record<string, unknown>;
    }[] = [
      {
        chamar: (repo) =>
          repo.criarUnidade({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            nome: "Unidade Fictícia",
            validFrom: INICIO,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "estrutura.unidade.criar",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          nome: "Unidade Fictícia",
          validFrom: INICIO,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.renomearUnidade({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            unidadeId: UNIDADE,
            nome: "Unidade Renomeada",
            expectedVersion: 1,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "estrutura.unidade.renomear",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          unidadeId: UNIDADE,
          nome: "Unidade Renomeada",
          expectedVersion: 1,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.encerrarUnidade({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            unidadeId: UNIDADE,
            validTo: FIM,
            expectedVersion: 2,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "estrutura.unidade.encerrar",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          unidadeId: UNIDADE,
          validTo: FIM,
          expectedVersion: 2,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.definirParentUnidade({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            unidadeId: UNIDADE,
            parentUnitId: null,
            validFrom: INICIO,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "estrutura.unidade.parent.definir",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          unidadeId: UNIDADE,
          parentUnitId: null,
          validFrom: INICIO,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.encerrarParentUnidade({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            unidadeId: UNIDADE,
            validTo: FIM,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "estrutura.unidade.parent.encerrar",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          unidadeId: UNIDADE,
          validTo: FIM,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.criarPosicao({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            unidadeId: UNIDADE,
            jobRoleId: CARGO,
            seniorityLevelId: SENIORIDADE,
            validFrom: INICIO,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "estrutura.posicao.criar",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          unidadeId: UNIDADE,
          jobRoleId: CARGO,
          seniorityLevelId: SENIORIDADE,
          validFrom: INICIO,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.encerrarPosicao({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            posicaoId: POSICAO,
            validTo: FIM,
            expectedVersion: 3,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "estrutura.posicao.encerrar",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          posicaoId: POSICAO,
          validTo: FIM,
          expectedVersion: 3,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.definirColegiado({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            collaboratorId: COLABORADOR,
            memberCollaboratorIds: [MEMBRO],
            validFrom: INICIO,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "estrutura.colegiado.definir",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          collaboratorId: COLABORADOR,
          memberCollaboratorIds: [MEMBRO],
          validFrom: INICIO,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.definirColegiado({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            collaboratorId: COLABORADOR,
            memberCollaboratorIds: [],
            validFrom: INICIO,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "estrutura.colegiado.definir",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          collaboratorId: COLABORADOR,
          memberCollaboratorIds: [],
          validFrom: INICIO,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.encerrarColegiado({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            collaboratorId: COLABORADOR,
            validTo: FIM,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "estrutura.colegiado.encerrar",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          collaboratorId: COLABORADOR,
          validTo: FIM,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.criarCargo({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            nome: "Cargo Fictício",
            code: "FICT",
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "catalogo.cargo.criar",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          nome: "Cargo Fictício",
          code: "FICT",
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.renomearCargo({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            jobRoleId: CARGO,
            nome: "Cargo Renomeado",
            expectedVersion: 4,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "catalogo.cargo.renomear",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          jobRoleId: CARGO,
          nome: "Cargo Renomeado",
          expectedVersion: 4,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.alterarStatusCargo({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            jobRoleId: CARGO,
            status: "disabled",
            expectedVersion: 5,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "catalogo.cargo.status.alterar",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          jobRoleId: CARGO,
          status: "disabled",
          expectedVersion: 5,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.criarSenioridade({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            nome: "Senioridade Fictícia",
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "catalogo.senioridade.criar",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          nome: "Senioridade Fictícia",
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.renomearSenioridade({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            seniorityLevelId: SENIORIDADE,
            nome: "Senioridade Renomeada",
            expectedVersion: 6,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "catalogo.senioridade.renomear",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          seniorityLevelId: SENIORIDADE,
          nome: "Senioridade Renomeada",
          expectedVersion: 6,
          motivo: MOTIVO,
        },
      },
      {
        chamar: (repo) =>
          repo.alterarStatusSenioridade({
            organizationId: ORG,
            operationId: OPERACAO_ID,
            seniorityLevelId: SENIORIDADE,
            status: "active",
            expectedVersion: 7,
            motivo: MOTIVO,
          }),
        esperado: {
          operacao: "catalogo.senioridade.status.alterar",
          organization_id: ORG,
          operationId: OPERACAO_ID,
          seniorityLevelId: SENIORIDADE,
          status: "active",
          expectedVersion: 7,
          motivo: MOTIVO,
        },
      },
    ];

    for (const caso of casos) {
      const { cliente, invocacoes } = clienteEdgeFalso(sucesso(UNIDADE));
      const repo = criarRepositorioColaboradoresSupabase(cliente);

      await caso.chamar(repo);

      expect(invocacoes).toHaveLength(1);
      expect(invocacoes[0]?.nome).toBe(FUNCAO_COLABORADORES);
      expect(invocacoes[0]?.body).toEqual(caso.esperado);
      // O cliente envia INTENÇÃO: nada de identidade, autorização ou credencial.
      const chaves = Object.keys(invocacoes[0]?.body ?? {});
      for (const proibido of [
        "actor",
        "actor_user_profile_id",
        "capability",
        "scope",
        "service_role",
        "token",
        "seniority_level",
      ]) {
        expect(chaves).not.toContain(proibido);
      }
    }
  });

  it("erro público da Edge é propagado como código, sem vazar mensagem interna", async () => {
    const { cliente } = clienteEdgeFalso({
      error: { context: { error: { code: "CONFLICT", message: "expected_version divergente" } } },
    });
    const repo = criarRepositorioColaboradoresSupabase(cliente);

    const resultado = await repo.renomearUnidade({
      organizationId: ORG,
      operationId: OPERACAO_ID,
      unidadeId: UNIDADE,
      nome: "Unidade Renomeada",
      expectedVersion: 1,
      motivo: MOTIVO,
    });

    expect(resultado).toEqual({
      ok: false,
      error: { code: "CONFLICT", message: "expected_version divergente" },
    });
  });
});

// ---------------------------------------------------------------------------
// Leitura soberana (RLS/D16)
// ---------------------------------------------------------------------------

interface Consulta {
  readonly tabela: string;
  readonly igualdades: readonly (readonly [string, unknown])[];
  readonly ordens: readonly (readonly [string, boolean])[];
}

type RespostaTabela = {
  readonly data?: unknown;
  readonly error?: { readonly code: string; readonly message: string } | null;
};

function clienteLeituraFalso(
  porTabela: Record<string, RespostaTabela>,
  sessao: { access_token?: string } | null
): { readonly cliente: SupabaseClient; readonly consultas: Consulta[] } {
  const consultas: Consulta[] = [];
  const cliente = {
    auth: {
      getSession: async () => ({ data: { session: sessao }, error: null }),
    },
    from(tabela: string) {
      const registro = { tabela, igualdades: [] as (readonly [string, unknown])[], ordens: [] as (readonly [string, boolean])[] };
      consultas.push(registro);
      const resposta = porTabela[tabela] ?? { data: [] };
      const construtor = {
        select: () => construtor,
        eq: (coluna: string, valor: unknown) => {
          registro.igualdades.push([coluna, valor]);
          return construtor;
        },
        order: (coluna: string, opcoes?: { ascending?: boolean }) => {
          registro.ordens.push([coluna, opcoes?.ascending !== false]);
          return construtor;
        },
        then: (resolver: (valor: unknown) => unknown) =>
          Promise.resolve(resolver({ data: resposta.data ?? null, error: resposta.error ?? null })),
      };
      return construtor;
    },
  } as unknown as SupabaseClient;
  return { cliente, consultas };
}

describe("F5-08 P4 — leitura soberana da estrutura (RLS own-tenant)", () => {
  it("sem sessão recusa com NOT_AUTHORIZED e NÃO consulta o PostgREST", async () => {
    const { cliente, consultas } = clienteLeituraFalso({}, null);
    const leitura = criarLeituraEstrutura(cliente);

    const resultado = await leitura.ler({ organizationId: ORG });

    expect(resultado).toEqual({
      ok: false,
      error: { code: "NOT_AUTHORIZED", message: "Sessão inválida. Entre novamente." },
    });
    expect(consultas).toEqual([]);
  });

  it("sem organização ativa recusa com FORBIDDEN (fail-closed)", async () => {
    const { cliente, consultas } = clienteLeituraFalso(
      {},
      { access_token: "token-ficticio" }
    );
    const leitura = criarLeituraEstrutura(cliente);

    const resultado = await leitura.ler({ organizationId: null });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("FORBIDDEN");
    expect(consultas).toEqual([]);
  });

  it("filtra o tenant em TODAS as consultas e projeta as linhas do servidor", async () => {
    const { cliente, consultas } = clienteLeituraFalso(
      {
        organizational_units: {
          data: [
            {
              id: UNIDADE,
              name: "Unidade Fictícia",
              valid_from: "2026-03-01T00:00:00.000Z",
              valid_to: null,
              version: 2,
            },
          ],
        },
        organizational_unit_parent_periods: {
          data: [
            {
              id: POSICAO,
              unit_id: UNIDADE,
              parent_unit_id: null,
              valid_from: "2026-03-01T00:00:00.000Z",
              valid_to: null,
              version: 1,
            },
          ],
        },
        organizational_positions: {
          data: [
            {
              id: POSICAO,
              unit_id: UNIDADE,
              job_role_id: CARGO,
              seniority_level_id: SENIORIDADE,
              valid_from: "2026-03-01T00:00:00.000Z",
              valid_to: null,
              version: 3,
            },
          ],
        },
        position_reporting_lines: { data: [] },
        occupations: {
          data: [
            {
              id: MEMBRO,
              collaborator_id: COLABORADOR,
              organizational_position_id: POSICAO,
              valid_from: "2026-03-01T00:00:00.000Z",
              valid_to: null,
              version: 1,
            },
          ],
        },
        job_roles: {
          data: [{ id: CARGO, code: "FICT", name: "Cargo Fictício", status: "active", version: 4 }],
        },
        seniority_levels: {
          data: [{ id: SENIORIDADE, name: "Pleno", status: "active", version: 5 }],
        },
        collegiate_configurations: {
          data: [
            {
              id: POSICAO,
              collaborator_id: COLABORADOR,
              valid_from: "2026-03-01T00:00:00.000Z",
              valid_to: null,
              version: 6,
            },
          ],
        },
        collegiate_configuration_members: {
          data: [{ configuration_id: POSICAO, member_collaborator_id: MEMBRO }],
        },
        collaborators: { data: [{ id: COLABORADOR, full_name: "Maria Silva" }] },
      },
      { access_token: "token-ficticio" }
    );
    const leitura = criarLeituraEstrutura(cliente);

    const resultado = await leitura.ler({ organizationId: ORG });

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    const dados = resultado.data;
    expect(dados.unidades[0]).toMatchObject({ unitId: UNIDADE, nome: "Unidade Fictícia" });
    expect(dados.periodosParent[0]).toMatchObject({ unitId: UNIDADE, parentUnitId: null });
    expect(dados.posicoes[0]).toMatchObject({ posicaoId: POSICAO, seniorityLevelId: SENIORIDADE });
    expect(dados.ocupacoes[0]).toMatchObject({ posicaoId: POSICAO, collaboratorId: COLABORADOR });
    expect(dados.cargos[0]).toMatchObject({ jobRoleId: CARGO, code: "FICT", status: "active" });
    expect(dados.senioridades[0]).toMatchObject({ seniorityLevelId: SENIORIDADE, nome: "Pleno" });
    expect(dados.colegiados[0]).toMatchObject({ collaboratorId: COLABORADOR, membroIds: [MEMBRO] });
    expect(dados.colaboradores[0]).toEqual({ collaboratorId: COLABORADOR, nome: "Maria Silva" });

    // Defesa em profundidade: toda consulta é restrita ao tenant de intenção.
    expect(consultas).toHaveLength(10);
    for (const consulta of consultas) {
      expect(consulta.igualdades).toEqual([["organization_id", ORG]]);
    }
  });

  it("negação de RLS (42501) vira FORBIDDEN sem expor a mensagem do banco", async () => {
    const { cliente } = clienteLeituraFalso(
      {
        organizational_units: {
          data: null,
          error: { code: "42501", message: 'permission denied for table "organizational_units"' },
        },
      },
      { access_token: "token-ficticio" }
    );
    const leitura = criarLeituraEstrutura(cliente);

    const resultado = await leitura.ler({ organizationId: ORG });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("FORBIDDEN");
    expect(resultado.error.message).not.toContain("permission denied");
  });

  it("falha inesperada vira INTERNAL sem vazar detalhe do banco", async () => {
    const { cliente } = clienteLeituraFalso(
      {
        job_roles: { data: null, error: { code: "42P01", message: 'relation "x" does not exist' } },
      },
      { access_token: "token-ficticio" }
    );
    const leitura = criarLeituraEstrutura(cliente);

    const resultado = await leitura.ler({ organizationId: ORG });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("INTERNAL");
    expect(resultado.error.message).not.toContain("does not exist");
  });
});
