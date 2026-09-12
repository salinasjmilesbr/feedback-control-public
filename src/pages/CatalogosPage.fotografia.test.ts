/**
 * F5-08 P4 (correção do BLOCKER 2) — EXPECTED VERSION e FOTOGRAFIA ALTERADA.
 *
 * Simula o fluxo exigido pela auditoria:
 *   1. abrir edição de cargo/senioridade (fotografia A, com a entidade);
 *   2. a fotografia muda antes da submissão (fotografia B, sem a entidade);
 *   3. confirmar que NENHUMA mutação é enviada, que NENHUM `expectedVersion: 0`
 *      (ou qualquer default) é criado, que a UI recebe o estado
 *      desatualizado/conflito e que o chamador recarrega a leitura.
 *
 * A confirmação usa a porta injetada — nenhuma rede, nenhum Supabase real.
 */

import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  confirmarEdicaoCatalogo,
  type EntradaConfirmarEdicaoCatalogo,
} from "./catalogosEdicao";
import type { ServiceColaboradores } from "../services/colaboradoresSoberanos/serviceColaboradores";
import type { EstruturaSoberana } from "../infrastructure/supabase/estrutura/repositorioEstruturaSoberana";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";

const ORG = "11111111-1111-4111-8111-111111111111";
const CARGO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const SENIORIDADE = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee";
const OUTRO_CARGO = "dfdfdfdf-dfdf-4fdf-8fdf-dfdfdfdfdfdf";
const OPERACAO_ID = "66666666-6666-4666-8666-666666666666";
const MOTIVO = "ajuste de nomenclatura";

interface Chamada {
  readonly metodo: string;
  readonly argumentos: unknown;
}

function estruturaCom(
  cargos: EstruturaSoberana["cargos"],
  senioridades: EstruturaSoberana["senioridades"] = [
    {
      seniorityLevelId: SENIORIDADE,
      nome: "Pleno",
      status: "active",
      version: 9,
    },
  ]
): EstruturaSoberana {
  return {
    unidades: [],
    periodosParent: [],
    posicoes: [],
    reportingLines: [],
    ocupacoes: [],
    cargos,
    senioridades,
    colegiados: [],
    colaboradores: [],
  };
}

/** Fotografia A: contém o cargo em edição (versão 4) e a senioridade (versão 9). */
const FOTOGRAFIA_A = estruturaCom([
  { jobRoleId: CARGO, code: "FICT", nome: "Cargo Fictício", status: "active", version: 4 },
]);

/** Fotografia B: o cargo em edição SUMIU da leitura (recarga concorrente). */
const FOTOGRAFIA_B = estruturaCom([
  {
    jobRoleId: OUTRO_CARGO,
    code: "OUTR",
    nome: "Outro Cargo Fictício",
    status: "active",
    version: 1,
  },
]);

type ServicoFalso = ServiceColaboradores & { readonly chamadas: readonly Chamada[] };

function servicoFalso(): ServicoFalso {
  const chamadas: Chamada[] = [];
  const registrar = <T>(metodo: string, argumentos: unknown, dados: T) => {
    chamadas.push({ metodo, argumentos });
    return Promise.resolve({ ok: true, dados } as const);
  };
  const padrao = {
    renomearCargo: (entrada: unknown) => registrar("renomearCargo", entrada, 5),
    alterarStatusCargo: (entrada: unknown) => registrar("alterarStatusCargo", entrada, 6),
    renomearSenioridade: (entrada: unknown) => registrar("renomearSenioridade", entrada, 10),
    alterarStatusSenioridade: (entrada: unknown) =>
      registrar("alterarStatusSenioridade", entrada, 11),
  };
  return { ...padrao, chamadas } as unknown as ServicoFalso;
}

function entrada(
  parcial: Partial<EntradaConfirmarEdicaoCatalogo> = {}
): EntradaConfirmarEdicaoCatalogo {
  return {
    estrutura: FOTOGRAFIA_A,
    edicao: { tipo: "cargo", id: CARGO, acao: "renomear", statusAtual: "active" },
    nome: "Cargo Renomeado",
    motivo: MOTIVO,
    operationId: OPERACAO_ID,
    organizationId: ORG,
    ...parcial,
  };
}

beforeEach(() => {
  instalarLocalStorageEmMemoria();
});

describe("F5-08 P4 — edição de catálogo sobre fotografia ALTERADA", () => {
  it("item ausente na fotografia corrente: NENHUMA mutação, NENHUMA versão fabricada", async () => {
    const servico = servicoFalso();

    const desfecho = await confirmarEdicaoCatalogo(
      entrada({
        estrutura: FOTOGRAFIA_B,
        edicao: { tipo: "cargo", id: CARGO, acao: "renomear", statusAtual: "active" },
      }),
      { operacoes: servico }
    );

    // 1) nada é enviado à porta/Edge
    expect(servico.chamadas).toEqual([]);
    // 2) desfecho público de estado desatualizado (o chamador recarrega a leitura)
    expect(desfecho).toEqual({
      tipo: "fotografia-desatualizada",
      codigo: "CONFLICT",
      mensagem:
        "A estrutura foi atualizada e o item em edição não está mais na leitura atual. " +
        "A leitura foi recarregada: revise o estado e tente novamente.",
    });
    // 3) nenhuma versão fabricada em lugar algum do desfecho
    expect(JSON.stringify(desfecho)).not.toContain("expectedVersion");
  });

  it("o mesmo vale para senioridade removida da fotografia", async () => {
    const servico = servicoFalso();
    const base = estruturaCom([], []);

    const desfecho = await confirmarEdicaoCatalogo(
      entrada({
        estrutura: base,
        edicao: {
          tipo: "senioridade",
          id: SENIORIDADE,
          acao: "status",
          statusAtual: "active",
        },
      }),
      { operacoes: servico }
    );

    expect(servico.chamadas).toEqual([]);
    expect(desfecho.tipo).toBe("fotografia-desatualizada");
  });

  it("item presente na fotografia: envia a versão LIDA (nunca 0/default)", async () => {
    const servico = servicoFalso();

    const desfecho = await confirmarEdicaoCatalogo(entrada(), { operacoes: servico });

    expect(desfecho.tipo).toBe("concluida");
    expect(servico.chamadas).toEqual([
      {
        metodo: "renomearCargo",
        argumentos: {
          operationId: OPERACAO_ID,
          expectedVersion: 4,
          motivo: MOTIVO,
          organizationId: ORG,
          jobRoleId: CARGO,
          nome: "Cargo Renomeado",
        },
      },
    ]);
  });

  it("alteração de status usa a versão da fotografia e o status oposto", async () => {
    const servico = servicoFalso();

    await confirmarEdicaoCatalogo(
      entrada({
        edicao: { tipo: "cargo", id: CARGO, acao: "status", statusAtual: "active" },
      }),
      { operacoes: servico }
    );

    expect(servico.chamadas[0]?.metodo).toBe("alterarStatusCargo");
    expect(servico.chamadas[0]?.argumentos).toMatchObject({
      jobRoleId: CARGO,
      status: "disabled",
      expectedVersion: 4,
    });
  });

  it("sem motivo, nada é enviado (forma obrigatória)", async () => {
    const servico = servicoFalso();

    const desfecho = await confirmarEdicaoCatalogo(entrada({ motivo: "   " }), {
      operacoes: servico,
    });

    expect(desfecho).toEqual({ tipo: "sem-motivo" });
    expect(servico.chamadas).toEqual([]);
  });

  it("nenhuma edição grava em localStorage", async () => {
    const armazenamento = instalarLocalStorageEmMemoria();
    const escrever = vi.spyOn(armazenamento, "setItem");

    await confirmarEdicaoCatalogo(entrada(), { operacoes: servicoFalso() });
    await confirmarEdicaoCatalogo(entrada({ estrutura: FOTOGRAFIA_B }), {
      operacoes: servicoFalso(),
    });

    expect(escrever).not.toHaveBeenCalled();
  });
});
