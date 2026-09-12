/**
 * F5-08 P4 — testes da PORTA do cliente para ESTRUTURA e CATÁLOGOS.
 *
 * Prova o que o P4 exige da porta:
 * - as 15 operações administrativas do P3 são expostas e propagam a INTENÇÃO
 *   (`operationId`, `expectedVersion`, vigência e `motivo`) SEM alterá-la;
 * - nenhuma identidade/tenant é fabricada no cliente (sem `actor`,
 *   `capability`, `scope`, `service_role` no payload);
 * - negação (`FORBIDDEN`/`NOT_FOUND`/`CONFLICT`) nunca vira exceção e nunca é
 *   reexecutada automaticamente;
 * - a leitura soberana (RLS/D16) devolve a fotografia do servidor e falha de
 *   forma explícita quando não há caminho;
 * - nada é gravado em `localStorage` em nenhuma operação.
 */

import { beforeEach, describe, expect, it, vi } from "vitest";
import * as porta from "./acessoColaboradoresSoberanos";
import { redefinirAcessoColaboradoresSoberanos } from "./acessoColaboradoresSoberanos";
import type { ServiceColaboradores } from "./serviceColaboradores";
import type { EstruturaSoberana } from "../../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import { instalarLocalStorageEmMemoria } from "../../test/localStorageMock";

const ORG = "11111111-1111-4111-8111-111111111111";
const OUTRA_ORG = "99999999-9999-4999-8999-999999999999";
const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const UNIDADE_PAI = "abababab-abab-4bab-8bab-abababababab";
const POSICAO = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const COLABORADOR = "22222222-2222-4222-8222-222222222222";
const MEMBRO = "33333333-3333-4333-8333-333333333333";
const CARGO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const SENIORIDADE = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const OPERACAO_ID = "66666666-6666-4666-8666-666666666666";
const INICIO = "2026-03-01";
const FIM = "2026-06-30";
const MOTIVO = "reorganização aprovada";

interface Chamada {
  readonly metodo: string;
  readonly argumentos: unknown;
}

type ServicoFalso = ServiceColaboradores & { readonly chamadas: readonly Chamada[] };

function estruturaSoberana(): EstruturaSoberana {
  return {
    unidades: [
      { unitId: UNIDADE, nome: "Unidade Fictícia", validFrom: INICIO, validTo: null, version: 1 },
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

function servicoFalso(
  comportamentos: Partial<ServiceColaboradores> = {}
): ServicoFalso {
  const chamadas: Chamada[] = [];
  const registrar = <T>(metodo: string, argumentos: unknown, dados: T) => {
    chamadas.push({ metodo, argumentos });
    return Promise.resolve({ ok: true, dados } as const);
  };

  const padrao = {
    lerEstrutura: (entrada: unknown) => registrar("lerEstrutura", entrada, estruturaSoberana()),
    criarUnidade: (entrada: unknown) => registrar("criarUnidade", entrada, UNIDADE),
    renomearUnidade: (entrada: unknown) => registrar("renomearUnidade", entrada, 2),
    encerrarUnidade: (entrada: unknown) => registrar("encerrarUnidade", entrada, 3),
    definirParentUnidade: (entrada: unknown) => registrar("definirParentUnidade", entrada, UNIDADE),
    encerrarParentUnidade: (entrada: unknown) =>
      registrar("encerrarParentUnidade", entrada, UNIDADE),
    criarPosicao: (entrada: unknown) => registrar("criarPosicao", entrada, POSICAO),
    encerrarPosicao: (entrada: unknown) => registrar("encerrarPosicao", entrada, 4),
    definirColegiado: (entrada: unknown) => registrar("definirColegiado", entrada, UNIDADE),
    encerrarColegiado: (entrada: unknown) => registrar("encerrarColegiado", entrada, UNIDADE),
    criarCargo: (entrada: unknown) => registrar("criarCargo", entrada, CARGO),
    renomearCargo: (entrada: unknown) => registrar("renomearCargo", entrada, 5),
    alterarStatusCargo: (entrada: unknown) => registrar("alterarStatusCargo", entrada, 6),
    criarSenioridade: (entrada: unknown) => registrar("criarSenioridade", entrada, SENIORIDADE),
    renomearSenioridade: (entrada: unknown) => registrar("renomearSenioridade", entrada, 7),
    alterarStatusSenioridade: (entrada: unknown) =>
      registrar("alterarStatusSenioridade", entrada, 8),
  };

  return { ...padrao, ...comportamentos, chamadas } as unknown as ServicoFalso;
}

type Caso = {
  readonly nome: string;
  readonly metodo: string;
  readonly chamar: (servico: ServiceColaboradores) => Promise<unknown>;
  readonly argumentos: unknown;
};

const CASOS: readonly Caso[] = [
  {
    nome: "criarUnidade",
    metodo: "criarUnidade",
    argumentos: {
      operationId: OPERACAO_ID,
      nome: "Nova Unidade Fictícia",
      validFrom: INICIO,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.criarUnidade(
        {
          operationId: OPERACAO_ID,
          nome: "Nova Unidade Fictícia",
          validFrom: INICIO,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "renomearUnidade",
    metodo: "renomearUnidade",
    argumentos: {
      operationId: OPERACAO_ID,
      unidadeId: UNIDADE,
      nome: "Unidade Renomeada",
      expectedVersion: 1,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.renomearUnidade(
        {
          operationId: OPERACAO_ID,
          unidadeId: UNIDADE,
          nome: "Unidade Renomeada",
          expectedVersion: 1,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "encerrarUnidade",
    metodo: "encerrarUnidade",
    argumentos: {
      operationId: OPERACAO_ID,
      unidadeId: UNIDADE,
      validTo: FIM,
      expectedVersion: 1,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.encerrarUnidade(
        {
          operationId: OPERACAO_ID,
          unidadeId: UNIDADE,
          validTo: FIM,
          expectedVersion: 1,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "definirParentUnidade (raiz)",
    metodo: "definirParentUnidade",
    argumentos: {
      operationId: OPERACAO_ID,
      unidadeId: UNIDADE,
      parentUnitId: null,
      validFrom: INICIO,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.definirParentUnidade(
        {
          operationId: OPERACAO_ID,
          unidadeId: UNIDADE,
          parentUnitId: null,
          validFrom: INICIO,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "definirParentUnidade (com pai)",
    metodo: "definirParentUnidade",
    argumentos: {
      operationId: OPERACAO_ID,
      unidadeId: UNIDADE,
      parentUnitId: UNIDADE_PAI,
      validFrom: INICIO,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.definirParentUnidade(
        {
          operationId: OPERACAO_ID,
          unidadeId: UNIDADE,
          parentUnitId: UNIDADE_PAI,
          validFrom: INICIO,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "encerrarParentUnidade",
    metodo: "encerrarParentUnidade",
    argumentos: {
      operationId: OPERACAO_ID,
      unidadeId: UNIDADE,
      validTo: FIM,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.encerrarParentUnidade(
        {
          operationId: OPERACAO_ID,
          unidadeId: UNIDADE,
          validTo: FIM,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "criarPosicao",
    metodo: "criarPosicao",
    argumentos: {
      operationId: OPERACAO_ID,
      unidadeId: UNIDADE,
      jobRoleId: CARGO,
      seniorityLevelId: SENIORIDADE,
      validFrom: INICIO,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.criarPosicao(
        {
          operationId: OPERACAO_ID,
          unidadeId: UNIDADE,
          jobRoleId: CARGO,
          seniorityLevelId: SENIORIDADE,
          validFrom: INICIO,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "criarPosicao sem senioridade",
    metodo: "criarPosicao",
    argumentos: {
      operationId: OPERACAO_ID,
      unidadeId: UNIDADE,
      jobRoleId: CARGO,
      seniorityLevelId: null,
      validFrom: INICIO,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.criarPosicao(
        {
          operationId: OPERACAO_ID,
          unidadeId: UNIDADE,
          jobRoleId: CARGO,
          seniorityLevelId: null,
          validFrom: INICIO,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "encerrarPosicao",
    metodo: "encerrarPosicao",
    argumentos: {
      operationId: OPERACAO_ID,
      posicaoId: POSICAO,
      validTo: FIM,
      expectedVersion: 2,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.encerrarPosicao(
        {
          operationId: OPERACAO_ID,
          posicaoId: POSICAO,
          validTo: FIM,
          expectedVersion: 2,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "definirColegiado com membros",
    metodo: "definirColegiado",
    argumentos: {
      operationId: OPERACAO_ID,
      collaboratorId: COLABORADOR,
      memberCollaboratorIds: [MEMBRO],
      validFrom: INICIO,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.definirColegiado(
        {
          operationId: OPERACAO_ID,
          collaboratorId: COLABORADOR,
          memberCollaboratorIds: [MEMBRO],
          validFrom: INICIO,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "definirColegiado com lista VAZIA (sem colegiado explícito)",
    metodo: "definirColegiado",
    argumentos: {
      operationId: OPERACAO_ID,
      collaboratorId: COLABORADOR,
      memberCollaboratorIds: [],
      validFrom: INICIO,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.definirColegiado(
        {
          operationId: OPERACAO_ID,
          collaboratorId: COLABORADOR,
          memberCollaboratorIds: [],
          validFrom: INICIO,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "encerrarColegiado",
    metodo: "encerrarColegiado",
    argumentos: {
      operationId: OPERACAO_ID,
      collaboratorId: COLABORADOR,
      validTo: FIM,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.encerrarColegiado(
        {
          operationId: OPERACAO_ID,
          collaboratorId: COLABORADOR,
          validTo: FIM,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "criarCargo",
    metodo: "criarCargo",
    argumentos: {
      operationId: OPERACAO_ID,
      nome: "Cargo Fictício",
      code: "FICT",
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.criarCargo(
        {
          operationId: OPERACAO_ID,
          nome: "Cargo Fictício",
          code: "FICT",
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "renomearCargo",
    metodo: "renomearCargo",
    argumentos: {
      operationId: OPERACAO_ID,
      jobRoleId: CARGO,
      nome: "Cargo Renomeado",
      expectedVersion: 1,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.renomearCargo(
        {
          operationId: OPERACAO_ID,
          jobRoleId: CARGO,
          nome: "Cargo Renomeado",
          expectedVersion: 1,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "alterarStatusCargo",
    metodo: "alterarStatusCargo",
    argumentos: {
      operationId: OPERACAO_ID,
      jobRoleId: CARGO,
      status: "disabled",
      expectedVersion: 1,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.alterarStatusCargo(
        {
          operationId: OPERACAO_ID,
          jobRoleId: CARGO,
          status: "disabled",
          expectedVersion: 1,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "criarSenioridade",
    metodo: "criarSenioridade",
    argumentos: {
      operationId: OPERACAO_ID,
      nome: "Senioridade Fictícia",
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.criarSenioridade(
        {
          operationId: OPERACAO_ID,
          nome: "Senioridade Fictícia",
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "renomearSenioridade",
    metodo: "renomearSenioridade",
    argumentos: {
      operationId: OPERACAO_ID,
      seniorityLevelId: SENIORIDADE,
      nome: "Senioridade Renomeada",
      expectedVersion: 1,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.renomearSenioridade(
        {
          operationId: OPERACAO_ID,
          seniorityLevelId: SENIORIDADE,
          nome: "Senioridade Renomeada",
          expectedVersion: 1,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
  {
    nome: "alterarStatusSenioridade",
    metodo: "alterarStatusSenioridade",
    argumentos: {
      operationId: OPERACAO_ID,
      seniorityLevelId: SENIORIDADE,
      status: "active",
      expectedVersion: 1,
      motivo: MOTIVO,
      organizationId: OUTRA_ORG,
    },
    chamar: (operacoes) =>
      porta.alterarStatusSenioridade(
        {
          operationId: OPERACAO_ID,
          seniorityLevelId: SENIORIDADE,
          status: "active",
          expectedVersion: 1,
          motivo: MOTIVO,
          organizationId: OUTRA_ORG,
        },
        { operacoes }
      ),
  },
];

let armazenamento: Storage;

beforeEach(() => {
  armazenamento = instalarLocalStorageEmMemoria();
  redefinirAcessoColaboradoresSoberanos();
});

describe("F5-08 P4 — porta da estrutura: propagação fiel e sem autoridade local", () => {
  it.each(CASOS)("$nome propaga a intenção EXATA ao service", async (caso) => {
    const servico = servicoFalso();

    const resultado = await caso.chamar(servico);

    expect(resultado).toMatchObject({ ok: true });
    expect(servico.chamadas).toHaveLength(1);
    expect(servico.chamadas[0]?.metodo).toBe(caso.metodo);
    expect(servico.chamadas[0]?.argumentos).toEqual(caso.argumentos);
  });

  it("nenhum payload carrega ator, capability, escopo ou credencial privilegiada", async () => {
    for (const caso of CASOS) {
      const servico = servicoFalso();
      await caso.chamar(servico);
      const serializado = JSON.stringify(servico.chamadas[0]?.argumentos);
      expect(serializado).not.toMatch(/actor|capability|scope|service_role|token/i);
      expect(servico.chamadas[0]?.argumentos).toHaveProperty("operationId");
    }
  });

  it("mutações de linha existente carregam expectedVersion; colegiado aceita lista vazia", async () => {
    const comVersao = CASOS.filter(
      (caso) =>
        caso.metodo === "renomearUnidade" ||
        caso.metodo === "encerrarUnidade" ||
        caso.metodo === "encerrarPosicao" ||
        caso.metodo === "renomearCargo" ||
        caso.metodo === "alterarStatusCargo" ||
        caso.metodo === "renomearSenioridade" ||
        caso.metodo === "alterarStatusSenioridade"
    );
    expect(comVersao.length).toBeGreaterThan(0);
    for (const caso of comVersao) {
      expect(caso.argumentos).toHaveProperty("expectedVersion");
    }

    const listaVazia = CASOS.find(
      (caso) => caso.nome === "definirColegiado com lista VAZIA (sem colegiado explícito)"
    );
    expect(listaVazia?.argumentos).toMatchObject({ memberCollaboratorIds: [] });
  });

  it("negação do service volta como resultado e NÃO é reexecutada (sem retry)", async () => {
    const negar = vi.fn(async () => ({
      ok: false as const,
      codigo: "FORBIDDEN" as const,
      mensagem: "Você não tem permissão para esta operação.",
    }));
    const servico = servicoFalso({ criarUnidade: negar } as Partial<ServiceColaboradores>);

    const resultado = await porta.criarUnidade(
      {
        operationId: OPERACAO_ID,
        nome: "Unidade Fictícia",
        validFrom: INICIO,
        motivo: MOTIVO,
        organizationId: ORG,
      },
      { operacoes: servico }
    );

    expect(resultado).toEqual({
      ok: false,
      codigo: "FORBIDDEN",
      mensagem: "Você não tem permissão para esta operação.",
    });
    expect(negar).toHaveBeenCalledTimes(1);
  });

  it("nenhuma operação escreve em localStorage", async () => {
    const escrever = vi.spyOn(armazenamento, "setItem");
    for (const caso of CASOS) {
      await caso.chamar(servicoFalso());
    }
    await porta.lerEstrutura({ organizationId: ORG }, { operacoes: servicoFalso() });
    expect(escrever).not.toHaveBeenCalled();
  });
});

describe("F5-08 P4 — porta da estrutura: leitura soberana (RLS/D16)", () => {
  it("lerEstrutura propaga a organização como INTENÇÃO e devolve a fotografia", async () => {
    const servico = servicoFalso();

    const resultado = await porta.lerEstrutura({ organizationId: ORG }, { operacoes: servico });

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.dados.unidades[0]?.unitId).toBe(UNIDADE);
    expect(servico.chamadas).toEqual([
      { metodo: "lerEstrutura", argumentos: { organizationId: ORG } },
    ]);
  });

  it("falha da leitura (sem sessão/organização) é resultado explícito, nunca vazio silencioso", async () => {
    const servico = servicoFalso({
      lerEstrutura: async () => ({
        ok: false as const,
        codigo: "NOT_AUTHORIZED" as const,
        mensagem: "Sessão inválida. Entre novamente.",
      }),
    } as Partial<ServiceColaboradores>);

    const resultado = await porta.lerEstrutura({ organizationId: ORG }, { operacoes: servico });

    expect(resultado).toEqual({
      ok: false,
      codigo: "NOT_AUTHORIZED",
      mensagem: "Sessão inválida. Entre novamente.",
    });
  });
});
