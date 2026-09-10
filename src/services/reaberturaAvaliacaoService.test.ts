import { beforeEach, describe, expect, it, vi } from "vitest";
import { can } from "../authorization/authorizationPolicy";
import type { AuthorizationContext } from "../authorization/AuthorizationContext";
import type { EvaluationResource } from "../authorization/ResourceContext";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import { criarArmazenamentoMemoria } from "../infrastructure/supabase/avaliacoes/cutover";
import { criarCutoverAvaliacoes } from "./avaliacoesSoberanas/cutoverAvaliacoesService";
import type { RepositorioAvaliacoes } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes";
import type { CicloAvaliacao } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import { reabrirAvaliacao } from "./reaberturaAvaliacaoService";

/**
 * F5-06 (Issue #103) — REABERTURA SOBERANA.
 *
 * A reabertura deixou de ser decidida/executada no navegador: o serviço envia a
 * INTENÇÃO (id + motivo + organização ativa) e o Policy Engine decide ALLOW/DENY
 * com a capability `evaluation.reopen` server-side. O estado do domínio
 * (reabertura exige `CONCLUIDA`, ciclo não encerrado/cancelado) também é
 * responsabilidade do servidor — por isso os cenários abaixo verificam a
 * DELEGAÇÃO e o fail-closed, e não uma cópia local das regras.
 *
 * A verificação de capability/scope que antes vivia aqui permanece coberta pelo
 * Policy Engine (ver `authorization/f4-09-functional.test.ts`); mantemos neste
 * arquivo apenas a checagem de UX (`can`) que a tela usa.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const AVALIACAO = "33333333-3333-4333-8333-333333333333";
const CHAVE_LEGADO = "feedback-control-feedbacks";

function pessoa(
  matricula: number,
  funcao: Colaborador["funcao"],
  gestorDiretoMatricula?: number,
  colegiado?: number[]
): Colaborador {
  return {
    matricula,
    status: "ATIVO",
    nome: `Pessoa ${matricula}`,
    email: `${matricula}@example.com`,
    cargo: funcao ?? "Sem função",
    area: "Área fictícia",
    funcao,
    gestorDiretoMatricula,
    avaliadoresColegiadoMatriculas: colegiado,
    respondePara: "",
  };
}

const gerente = pessoa(1, "GERENTE");
const coordenador = pessoa(2, "COORDENADOR", gerente.matricula);
const colegiado = pessoa(3, "COORDENADOR", gerente.matricula);
const avaliado = pessoa(4, "ANALISTA", coordenador.matricula, [colegiado.matricula]);
const colaboradores = [gerente, coordenador, colegiado, avaliado];
const ciclo: CicloAvaliacao = {
  id: "ciclo-reabertura",
  ano: 2026,
  ciclo: 1,
  status: "ATIVO",
  dataCriacao: "2026-01-01T00:00:00.000Z",
  dataUltimaAtualizacao: "2026-01-01T00:00:00.000Z",
};

function contexto(actor: Colaborador): AuthorizationContext {
  return {
    actor: {
      matricula: actor.matricula,
      funcao: actor.funcao,
      status: actor.status,
    },
  };
}

function repositorioFalso(
  comportamentos: Partial<RepositorioAvaliacoes> = {}
): RepositorioAvaliacoes & { readonly chamadas: string[] } {
  const chamadas: string[] = [];
  const base: RepositorioAvaliacoes = {
    criar: async () => ({ ok: true, data: AVALIACAO }),
    ler: async () => ({ ok: true, data: null }),
    gravarNotas: async () => ({ ok: true, data: null }),
    gravarComentario: async () => ({ ok: true, data: null }),
    concluir: async () => ({ ok: true, data: null }),
    reabrir: async () => ({ ok: true, data: null }),
    cancelar: async () => ({ ok: true, data: null }),
    realinharParticipantes: async () => ({ ok: true, data: 0 }),
    transparenciaDoAvaliado: async () => {
      throw new Error("não usado neste teste");
    },
    painelParticipante: async () => {
      throw new Error("não usado neste teste");
    },
    resolverCiclo: async () => ({ ok: true, data: "22222222-2222-4222-8222-222222222222" }),
  };

  const instrumentado = Object.fromEntries(
    Object.entries({ ...base, ...comportamentos }).map(([nome, fn]) => [
      nome,
      async (...args: unknown[]) => {
        chamadas.push(nome);
        return (fn as (...a: unknown[]) => unknown)(...args);
      },
    ])
  ) as unknown as RepositorioAvaliacoes;

  return Object.assign(instrumentado, { chamadas });
}

function deps(comportamentos: Partial<RepositorioAvaliacoes> = {}) {
  const repositorio = repositorioFalso(comportamentos);
  return {
    repositorio,
    criarCutover: () =>
      criarCutoverAvaliacoes({
        repositorio,
        armazenamento: criarArmazenamentoMemoria(),
      }),
  };
}

describe("reabrirAvaliacao (soberano)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(CHAVE_LEGADO, JSON.stringify([{ id: AVALIACAO }]));
  });

  it("envia a intenção ao servidor e NÃO escreve no localStorage", async () => {
    const dependencias = deps();
    const legadoAntes = localStorage.getItem(CHAVE_LEGADO);

    const resultado = await reabrirAvaliacao(
      AVALIACAO,
      "  Corrigir lançamento  ",
      ORG,
      dependencias
    );

    expect(resultado.ok).toBe(true);
    expect(dependencias.repositorio.chamadas).toEqual(["reabrir"]);
    // Sem dual-write: o histórico legado permanece intacto.
    expect(localStorage.getItem(CHAVE_LEGADO)).toBe(legadoAntes);
  });

  it("recusa motivo vazio antes de chamar o servidor", async () => {
    const dependencias = deps();

    await expect(
      reabrirAvaliacao(AVALIACAO, "   ", ORG, dependencias)
    ).rejects.toThrow("Informe o motivo da reabertura.");
    expect(dependencias.repositorio.chamadas).toEqual([]);
  });

  it.each(["FORBIDDEN", "CONFLICT"] as const)(
    "recusa %s do servidor vira erro público sem gravar localmente",
    async (code) => {
      const dependencias = deps({
        reabrir: async () => ({ ok: false, error: { code, message: "recusado" } }),
      });
      const legadoAntes = localStorage.getItem(CHAVE_LEGADO);

      const resultado = await reabrirAvaliacao(
        AVALIACAO,
        "Motivo válido",
        ORG,
        dependencias
      );

      expect(resultado.ok).toBe(false);
      expect(resultado.erro).toBeTruthy();
      expect(localStorage.getItem(CHAVE_LEGADO)).toBe(legadoAntes);
    }
  );

  it("sem caminho soberano configurado a operação é recusada (fail-closed)", async () => {
    const legadoAntes = localStorage.getItem(CHAVE_LEGADO);
    const resultado = await reabrirAvaliacao(AVALIACAO, "Motivo válido", ORG, {
      criarCutover: () => null,
    });

    expect(resultado.ok).toBe(false);
    expect(resultado.erro).toContain("PostgreSQL");
    expect(localStorage.getItem(CHAVE_LEGADO)).toBe(legadoAntes);
  });

  it("propaga erro de rede do repositório sem cair para o caminho legado", async () => {
    const dependencias = deps({
      reabrir: vi.fn(async () => {
        throw new Error("rede indisponível");
      }) as unknown as RepositorioAvaliacoes["reabrir"],
    });

    await expect(
      reabrirAvaliacao(AVALIACAO, "Motivo válido", ORG, dependencias)
    ).rejects.toThrow("rede indisponível");
    expect(localStorage.getItem(CHAVE_LEGADO)).not.toBeNull();
  });

  it("mantém a checagem de UX (can) coerente para os papéis da cadeia", () => {
    const resource: EvaluationResource = {
      kind: "evaluation",
      evaluatedCollaborator: avaliado,
      collaborators: colaboradores,
      cycle: ciclo,
      evaluationStatus: "CONCLUIDA",
    };

    // `can()` é SOMENTE UX; a decisão efetiva é do Policy Engine server-side.
    // Aqui garantimos apenas que a tela não libera edição para o próprio
    // avaliado, que não pertence à cadeia de gestão dele.
    expect(can(contexto(avaliado), "evaluation.edit.manager", resource)).toBe(false);
    expect(can(contexto(avaliado), "evaluation.edit.coordinator", resource)).toBe(false);
    expect(can(contexto(avaliado), "evaluation.edit.board", resource)).toBe(false);
  });
});
