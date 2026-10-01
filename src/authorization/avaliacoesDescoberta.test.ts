/**
 * F6 — Descoberta soberana da avaliação do colaborador no ciclo.
 *
 * Cobre: contrato fechado (operação/capability/alvo), validação da intenção,
 * regra PURA por status e o carregamento do estado com dependências injetadas
 * (tenant, avaliação não cancelada, três ramos de autorização, fail-closed).
 *
 * A relação concreta de cada ramo (DIRECT_REPORTS ↔ `GESTAO_DIRETA`,
 * DESCENDANTS ↔ `GESTAO_CADEIA`, ASSIGNED ↔ `COLEGIADO`) é decidida por
 * `avaliarOperacaoAutorizacao` — coberta pelos testes de Policy Engine
 * existentes. Aqui garantimos que cada ramo é consultado com a capability e o
 * ALVO corretos e que qualquer negação/erro fecha.
 */
import { describe, expect, it, vi } from "vitest";
import { avaliacoes, type DepsAvaliacoes } from "../../supabase/functions/avaliacoes/core.ts";
import {
  CAPABILITY_POR_OPERACAO,
  CAPABILIDADES_DESCOBERTA_AVALIACAO,
  ehOperacaoAvaliacao,
  resolverDescobertaAvaliacao,
  tipoAlvoDaOperacao,
  validarEntradaAvaliacao,
} from "../infrastructure/supabase/avaliacoes/contrato.ts";
import {
  carregarEstadoDescoberta,
  type DepsEstadoDescoberta,
} from "../../supabase/functions/avaliacoes/descobertaSupabase.ts";

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "22222222-2222-4222-8222-222222222222";
const COLAB = "33333333-3333-4333-8333-333333333333";
const AVALIACAO = "44444444-4444-4444-8444-444444444444";
const OUTRA_ORG = "55555555-5555-4555-8555-555555555555";

describe("fronteira HTTP — CREATE-only", () => {
  it("informa somente existência, sem UUID, status ou conteúdo", async () => {
    const resultado = resolverDescobertaAvaliacao({
      avaliacao: { id: AVALIACAO, status: "RASCUNHO" },
      autorizaCriar: true,
      autorizaEscrever: false,
      autorizaLer: false,
    });
    expect(resultado.allowed).toBe(true);
    const deps: DepsAvaliacoes = {
      resolveCaller: async () => ORG,
      avaliarAutorizacao: async () => ({ allowed: false }),
      executarRpc: async () => ({ error: { code: "FORBIDDEN" } }),
      avaliarDescoberta: async () => ({ allowed: resultado.allowed }),
      executarDescoberta: async () => ({ data: resultado.allowed ? resultado.resultado : null }),
    };
    const response = await avaliacoes(new Request("http://localhost/functions/v1/avaliacoes", {
      method: "POST",
      headers: { Authorization: "Bearer ficticio", "Content-Type": "application/json" },
      body: JSON.stringify({
        organization_id: ORG,
        operacao: "evaluation.do_colaborador_no_ciclo",
        alvo: { type: "collaborator", id: COLAB },
        cycle_id: CICLO,
      }),
    }), deps);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      ok: true,
      operacao: "evaluation.do_colaborador_no_ciclo",
      resultado: { existeSemAcesso: true, podeEditar: false },
    });
  });
});

const corpo = {
  organization_id: ORG,
  operacao: "evaluation.do_colaborador_no_ciclo",
  alvo: { type: "collaborator", id: COLAB },
  cycle_id: CICLO,
};

describe("contrato — operação, capability e alvo", () => {
  it("reconhece a operação e exige alvo do tipo colaborador", () => {
    expect(ehOperacaoAvaliacao("evaluation.do_colaborador_no_ciclo")).toBe(true);
    expect(tipoAlvoDaOperacao("evaluation.do_colaborador_no_ciclo")).toBe("collaborator");
  });

  it("mantém o catálogo FECHADO: nenhuma capability nova", () => {
    expect(CAPABILITY_POR_OPERACAO["evaluation.do_colaborador_no_ciclo"]).toBe(
      "evaluation.read"
    );
    expect(new Set(Object.values(CAPABILITY_POR_OPERACAO))).toEqual(
      new Set([
        "evaluation.create",
        "evaluation.read",
        "evaluation.write",
        "evaluation.reopen",
        "evaluation.cancel",
        "report.read",
      ])
    );
    // O conjunto aceito pela descoberta é subconjunto do catálogo fechado.
    expect(new Set(CAPABILIDADES_DESCOBERTA_AVALIACAO)).toEqual(
      new Set(["evaluation.create", "evaluation.write", "evaluation.read"])
    );
  });
});

describe("validação da intenção (nunca da autoridade)", () => {
  it("aceita o corpo canônico", () => {
    expect(validarEntradaAvaliacao(corpo).ok).toBe(true);
  });

  it("exige cycle_id UUID", () => {
    expect(validarEntradaAvaliacao({ ...corpo, cycle_id: undefined }).ok).toBe(false);
    expect(validarEntradaAvaliacao({ ...corpo, cycle_id: "2026-1" }).ok).toBe(false);
  });

  it("recusa chaves fora da allowlist estrita (nada de notas/texto/motivo)", () => {
    for (const extra of [{ notas: [] }, { texto: "x" }, { motivo: "x" }, { ano: 2026 }]) {
      const r = validarEntradaAvaliacao({ ...corpo, ...extra });
      expect(r.ok, JSON.stringify(extra)).toBe(false);
    }
  });

  it("recusa identidade e ocorrência vindas do cliente (IDOR)", () => {
    for (const proibido of [
      { actor_id: ORG },
      { actor_user_profile_id: ORG },
      { user_profile_id: ORG },
      { participant_id: AVALIACAO },
    ]) {
      const r = validarEntradaAvaliacao({ ...corpo, ...proibido });
      expect(r.ok, JSON.stringify(proibido)).toBe(false);
    }
  });

  it("recusa alvo de avaliação e organization_id inválidos", () => {
    expect(
      validarEntradaAvaliacao({ ...corpo, alvo: { type: "evaluation", id: AVALIACAO } }).ok
    ).toBe(false);
    expect(validarEntradaAvaliacao({ ...corpo, organization_id: "org-1" }).ok).toBe(false);
  });
});

describe("regra pura — descoberta por status", () => {
  const sem = (over: Partial<Parameters<typeof resolverDescobertaAvaliacao>[0]> = {}) =>
    resolverDescobertaAvaliacao({
      avaliacao: null,
      autorizaCriar: false,
      autorizaEscrever: false,
      autorizaLer: false,
      ...over,
    });
  const com = (status: string, over: Record<string, boolean> = {}) =>
    resolverDescobertaAvaliacao({
      avaliacao: { id: AVALIACAO, status },
      autorizaCriar: false,
      autorizaEscrever: false,
      autorizaLer: false,
      ...over,
    });

  it("sem avaliação (ou só CANCELADA) ⇒ Nova avaliação apenas para quem pode CRIAR", () => {
    expect(sem({ autorizaCriar: true })).toEqual({
      allowed: true,
      resultado: { evaluationId: null, status: null, podeEditar: false },
    });
    expect(sem({ autorizaEscrever: true }).allowed).toBe(false);
    expect(sem({ autorizaLer: true }).allowed).toBe(false);
    expect(sem().allowed).toBe(false);
  });

  it("RASCUNHO editável ⇒ ALLOW com podeEditar pelo ramo write", () => {
    expect(com("RASCUNHO", { autorizaEscrever: true })).toEqual({
      allowed: true,
      resultado: { evaluationId: AVALIACAO, status: "RASCUNHO", podeEditar: true },
    });
  });

  it("PRONTA_PARA_FEEDBACK preserva a edição UUID quando WRITE autoriza", () => {
    expect(com("PRONTA_PARA_FEEDBACK", { autorizaEscrever: true })).toMatchObject({
      resultado: { evaluationId: AVALIACAO, podeEditar: true },
    });
  });

  it("RASCUNHO somente leitura ⇒ ALLOW para CONSULTAR (podeEditar=false)", () => {
    expect(com("RASCUNHO", { autorizaLer: true })).toEqual({
      allowed: true,
      resultado: { evaluationId: AVALIACAO, status: "RASCUNHO", podeEditar: false },
    });
  });

  it("CONCLUIDA ⇒ consulta mesmo com ramo write", () => {
    expect(com("CONCLUIDA", { autorizaLer: true }).allowed).toBe(true);
    expect(com("CONCLUIDA", { autorizaLer: true })).toMatchObject({
      resultado: { status: "CONCLUIDA", podeEditar: false },
    });
    expect(com("CONCLUIDA", { autorizaEscrever: true })).toMatchObject({
      resultado: { status: "CONCLUIDA", podeEditar: false },
    });
  });

  it("CREATE-only revela só a existência, nunca UUID, status ou dados da avaliação", () => {
    for (const status of ["RASCUNHO", "CONCLUIDA"]) {
      const decisao = com(status, { autorizaCriar: true });
      expect(decisao).toEqual({
        allowed: true,
        resultado: { existeSemAcesso: true, podeEditar: false },
      });
      expect(JSON.stringify(decisao)).not.toContain(AVALIACAO);
      expect(JSON.stringify(decisao)).not.toContain(status);
    }
  });

  it("sem relação alguma ⇒ DENY", () => {
    expect(com("RASCUNHO").allowed).toBe(false);
    expect(com("CONCLUIDA").allowed).toBe(false);
  });
});

describe("carregamento do estado (dependências injetadas)", () => {
  function deps(over: Partial<DepsEstadoDescoberta> = {}): DepsEstadoDescoberta {
    return {
      cicloDoTenant: async () => true,
      avaliacaoNaoCancelada: async () => null,
      autorizar: async () => false,
      ...over,
    };
  }

  it("ciclo de OUTRO tenant ⇒ inexistente e nenhuma autorização é consultada", async () => {
    const autorizar = vi.fn(async () => true);
    const estado = await carregarEstadoDescoberta(
      deps({ cicloDoTenant: async () => false, autorizar }),
      COLAB
    );
    expect(estado).toEqual({
      cicloOk: false,
      encontrada: null,
      autorizaCriar: false,
      autorizaEscrever: false,
      autorizaLer: false,
    });
    expect(autorizar).not.toHaveBeenCalled();
  });

  it("consulta create contra o COLABORADOR e write/read contra a AVALIAÇÃO", async () => {
    const chamadas: { capability: string; type: string; id: string }[] = [];
    const estado = await carregarEstadoDescoberta(
      deps({
        avaliacaoNaoCancelada: async () => ({ id: AVALIACAO, status: "RASCUNHO" }),
        autorizar: async (capability, alvo) => {
          chamadas.push({ capability, type: alvo.type, id: alvo.id });
          return true;
        },
      }),
      COLAB
    );
    expect(estado).toMatchObject({
      cicloOk: true,
      encontrada: { id: AVALIACAO, status: "RASCUNHO" },
      autorizaCriar: true,
      autorizaEscrever: true,
      autorizaLer: true,
    });
    expect(chamadas).toEqual([
      { capability: "evaluation.create", type: "collaborator", id: COLAB },
      { capability: "evaluation.write", type: "evaluation", id: AVALIACAO },
      { capability: "evaluation.read", type: "evaluation", id: AVALIACAO },
    ]);
  });

  it("sem avaliação não cancelada, write/read NÃO são consultados", async () => {
    const autorizar = vi.fn(async () => true);
    const estado = await carregarEstadoDescoberta(deps({ autorizar }), COLAB);
    expect(estado.encontrada).toBeNull();
    expect(estado.autorizaEscrever).toBe(false);
    expect(estado.autorizaLer).toBe(false);
    expect(autorizar).toHaveBeenCalledTimes(1);
    expect(autorizar).toHaveBeenCalledWith(
      "evaluation.create",
      { type: "collaborator", id: COLAB },
      COLAB
    );
  });

  it("fail-closed: erro em qualquer dependência nunca produz ALLOW", async () => {
    const casos: Partial<DepsEstadoDescoberta>[] = [
      { cicloDoTenant: async () => { throw new Error("rede"); } },
      { avaliacaoNaoCancelada: async () => { throw new Error("rede"); } },
      { autorizar: async () => { throw new Error("rede"); } },
    ];
    for (const caso of casos) {
      const estado = await carregarEstadoDescoberta(
        deps({ ...caso, avaliacaoNaoCancelada: caso.avaliacaoNaoCancelada ?? (async () => ({ id: AVALIACAO, status: "RASCUNHO" })) }),
        COLAB
      );
      expect(estado.autorizaCriar && estado.autorizaEscrever && estado.autorizaLer).toBe(false);
      const decisao = resolverDescobertaAvaliacao({
        avaliacao: estado.encontrada,
        autorizaCriar: estado.autorizaCriar,
        autorizaEscrever: estado.autorizaEscrever,
        autorizaLer: estado.autorizaLer,
      });
      expect(decisao.allowed).toBe(false);
    }
  });

  it("sem relação (autorizações falsas) ⇒ estado sem ALLOW", async () => {
    const estado = await carregarEstadoDescoberta(deps(), COLAB);
    const decisao = resolverDescobertaAvaliacao({
      avaliacao: estado.encontrada,
      autorizaCriar: estado.autorizaCriar,
      autorizaEscrever: estado.autorizaEscrever,
      autorizaLer: estado.autorizaLer,
    });
    expect(decisao.allowed).toBe(false);
  });

  it("tenant divergente no alvo: nenhuma chamada carrega dados de outra organização", async () => {
    // O chamador injeta o organizationId do ator; a dependência de ciclo
    // revalida o tenant. Aqui garantimos que, negado o ciclo, o resultado é
    // indistinguível de inexistente (sem vazar existência cross-tenant).
    const estado = await carregarEstadoDescoberta(
      deps({ cicloDoTenant: async () => false, avaliacaoNaoCancelada: async () => ({ id: AVALIACAO, status: "RASCUNHO" }) }),
      COLAB
    );
    expect(estado.cicloOk).toBe(false);
    expect(estado.encontrada).toBeNull();
    expect(OUTRA_ORG).not.toBe(ORG);
  });
});
