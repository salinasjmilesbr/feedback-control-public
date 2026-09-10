import { describe, expect, it } from "vitest";
import { avaliacoes, type DepsAvaliacoes, type ExecucaoAvaliacao } from "../../supabase/functions/avaliacoes/core.ts";
import {
  avaliarOperacaoAutorizacao,
  type DepsContextoAutorizacao,
} from "./contextoAutorizacao.ts";
import { CAPABILITY_POR_OPERACAO } from "../infrastructure/supabase/avaliacoes/contrato.ts";
import type { Capability } from "./Capability.ts";
import type { AuthIdentity } from "../auth/tipos.ts";
import type { RecursoSoberanoCarregado } from "./resourceContextReal.ts";

/**
 * F5-06 (Issue #103) — teste de INTEGRAÇÃO da fronteira: Edge Function + Policy
 * Engine REAL (não mockado) + estado de domínio server-side.
 *
 * Comprova o achado 7 da auditoria: nenhuma operação de avaliação é executada
 * sem decisão ALLOW do engine, e a decisão vem de capability × scope × recurso
 * REAL — `evaluation_ator_valido` nas RPCs passa a ser defesa em profundidade.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const USER = "33333333-3333-4333-8333-333333333333";
const AVALIACAO = "44444444-4444-4444-8444-444444444444";
const CICLO = "55555555-5555-4555-8555-555555555555";
const GESTOR = "66666666-6666-4666-8666-666666666666";
const AVALIADO = "77777777-7777-4777-8777-777777777777";
const COLEGA = "88888888-8888-4888-8888-888888888888";
const PARTICIPANTE = "99999999-9999-4999-8999-999999999999";
const SUB = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";

function identidade(): AuthIdentity {
  return {
    authUserId: USER,
    perfil: { id: USER, status: "active" },
    memberships: [{ id: "m-1", organizationId: ORG, status: "active" }],
    organizacoes: [{ id: ORG, name: "Org sintetica" }],
  } as AuthIdentity;
}

interface Cenario {
  readonly capability?: Capability;
  readonly scopes?: readonly string[];
  readonly status?: string;
  readonly recurso?: RecursoSoberanoCarregado | null;
  readonly alvos?: Record<string, readonly { collaboratorId: string | null; positionId: string | null }[]>;
  readonly vinculo?: string | null;
}

/**
 * Fronteira REAL: `avaliarOperacaoAutorizacao` do F5-05 com dependências
 * soberanas sintéticas (identidade, vínculo, capabilities×scopes, alvos por
 * scope e recurso carregado).
 */
function fronteira(cenario: Cenario = {}): DepsContextoAutorizacao {
  const recurso =
    cenario.recurso === undefined
      ? ({
          kind: "evaluation",
          id: AVALIACAO,
          organizationId: ORG,
          evaluatedCollaboratorId: AVALIADO,
          cycleId: CICLO,
          status: cenario.status ?? "RASCUNHO",
        } as RecursoSoberanoCarregado)
      : cenario.recurso;

  return {
    agora: () => new Date("2026-02-01T10:00:00Z"),
    resolverIdentidade: async () => identidade(),
    resolverColaboradorVinculado: async () =>
      cenario.vinculo === undefined ? GESTOR : cenario.vinculo,
    resolverCapabilitiesEscopos: async () => [
      {
        capability: cenario.capability ?? "evaluation.write",
        scopes: (cenario.scopes ?? ["DESCENDANTS"]) as never,
      },
    ],
    resolverAlvosEscopo: async ({ scope }) => cenario.alvos?.[scope] ?? [],
    carregarRecurso: async () => recurso,
    // Contexto de domínio coerente com o tipo do alvo: para o recurso de
    // avaliação é o STATUS real; para a CRIAÇÃO (colaborador) é o ciclo vigente
    // e a aptidão do avaliado — ambos resolvidos server-side.
    carregarContextoAvaliacao: async ({ target }) =>
      target.type === "evaluation"
        ? { status: cenario.status ?? "RASCUNHO" }
        : { status: "CRIACAO", cicloPermiteNovaAvaliacao: true, avaliadoApto: true },
    resolverAssigned: async () => null,
  };
}

const ALVOS_DESCENDANTS = {
  DESCENDANTS: [{ collaboratorId: AVALIADO, positionId: null }],
};

function corpoAvaliacao(
  operacao: string,
  extras: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    organization_id: ORG,
    operacao,
    alvo: { type: "evaluation", id: AVALIACAO },
    ...extras,
  };
}

function requisicao(corpo: unknown): Request {
  return new Request("http://localhost/functions/v1/avaliacoes", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer ok" },
    body: JSON.stringify(corpo),
  });
}

function deps(cenario: Cenario) {
  const contexto = fronteira(cenario);
  const executadas: ExecucaoAvaliacao[] = [];
  const d: DepsAvaliacoes = {
    resolveCaller: async () => USER,
    avaliarAutorizacao: async ({ authUserId, organizationId, operacao, alvo }) => {
      const capability = CAPABILITY_POR_OPERACAO[operacao] as Capability;
      const decisao = await avaliarOperacaoAutorizacao(
        { authUserId, organizationId, capability, alvo },
        contexto
      );
      return decisao.allowed
        ? { allowed: true }
        : { allowed: false, code: decisao.denial?.publicCode ?? "FORBIDDEN" };
    },
    executarRpc: async (execucao) => {
      executadas.push(execucao);
      return { data: null, error: null };
    },
  };
  return { d, executadas };
}

describe("fronteira de avaliações: Edge + Policy Engine real + domínio", () => {
  it("gravação de notas com capability+scope adequados ⇒ ALLOW e RPC executada UMA vez", async () => {
    const { d, executadas } = deps({ capability: "evaluation.write", alvos: ALVOS_DESCENDANTS });
    const resposta = await avaliacoes(
      requisicao(
        corpoAvaliacao("evaluation.gravar_notas", {
          participant_id: PARTICIPANTE,
          notas: [{ subcriterion_id: SUB, nota: 4 }],
        })
      ),
      d
    );

    expect(resposta.status).toBe(200);
    expect(executadas).toHaveLength(1);
    expect(executadas[0]!.actorUserProfileId).toBe(USER);
  });

  it("ator SEM o scope necessário ⇒ 403 e a RPC NÃO é executada (achado 7)", async () => {
    // Ator tem `evaluation.write`, mas o escopo é SELF e o avaliado é outro.
    const { d, executadas } = deps({ capability: "evaluation.write", scopes: ["SELF"] });
    const resposta = await avaliacoes(
      requisicao(
        corpoAvaliacao("evaluation.gravar_notas", {
          participant_id: PARTICIPANTE,
          notas: [{ subcriterion_id: SUB, nota: 4 }],
        })
      ),
      d
    );

    expect(resposta.status).toBe(403);
    expect(executadas).toHaveLength(0);
  });

  it("ator sem a CAPABILITY da operação ⇒ 403 e nenhuma execução", async () => {
    // Só tem `evaluation.read`; a operação exige `evaluation.concluir` ⇒ write.
    const { d, executadas } = deps({ capability: "evaluation.read", alvos: ALVOS_DESCENDANTS });
    const resposta = await avaliacoes(requisicao(corpoAvaliacao("evaluation.concluir")), d);

    expect(resposta.status).toBe(403);
    expect(executadas).toHaveLength(0);
  });

  it("avaliação CONCLUIDA: o domínio nega escrita mesmo com capability+scope (D8)", async () => {
    const { d, executadas } = deps({
      capability: "evaluation.write",
      alvos: ALVOS_DESCENDANTS,
      status: "CONCLUIDA",
    });
    const resposta = await avaliacoes(
      requisicao(
        corpoAvaliacao("evaluation.gravar_comentario", {
          participant_id: PARTICIPANTE,
          escopo: "FINAL",
          texto: "fechamento",
        })
      ),
      d
    );

    // DOMAIN_STATE_INVALID ⇒ CONFLICT (409) e nada é executado.
    expect(resposta.status).toBe(409);
    expect(executadas).toHaveLength(0);
  });

  it("avaliação CONCLUIDA: reabertura continua ALLOW (capability própria)", async () => {
    const { d, executadas } = deps({
      capability: "evaluation.reopen",
      alvos: ALVOS_DESCENDANTS,
      status: "CONCLUIDA",
    });
    const resposta = await avaliacoes(
      requisicao(corpoAvaliacao("evaluation.reabrir", { motivo: "erro de nota" })),
      d
    );

    expect(resposta.status).toBe(200);
    expect(executadas).toHaveLength(1);
  });

  it("avaliação de OUTRO TENANT ⇒ 404 e nenhuma execução (cross-tenant)", async () => {
    const { d, executadas } = deps({
      capability: "evaluation.read",
      alvos: ALVOS_DESCENDANTS,
      recurso: {
        kind: "evaluation",
        id: AVALIACAO,
        organizationId: ORG_B,
        evaluatedCollaboratorId: AVALIADO,
        cycleId: CICLO,
      },
    });
    const resposta = await avaliacoes(requisicao(corpoAvaliacao("evaluation.ler")), d);

    expect(resposta.status).toBe(404);
    expect(executadas).toHaveLength(0);
  });

  it("o próprio AVALIADO lê a sua avaliação por SELF ⇒ ALLOW", async () => {
    const { d, executadas } = deps({
      capability: "evaluation.read",
      scopes: ["SELF"],
      alvos: { SELF: [{ collaboratorId: AVALIADO, positionId: null }] },
      vinculo: AVALIADO,
    });
    const resposta = await avaliacoes(requisicao(corpoAvaliacao("evaluation.ler")), d);

    expect(resposta.status).toBe(200);
    expect(executadas).toHaveLength(1);
  });

  it("o COLEGA (sem vínculo com o avaliado) NÃO lê ⇒ 403", async () => {
    const { d, executadas } = deps({
      capability: "evaluation.read",
      scopes: ["SELF"],
      alvos: { SELF: [] },
      vinculo: COLEGA,
    });
    const resposta = await avaliacoes(requisicao(corpoAvaliacao("evaluation.ler")), d);

    expect(resposta.status).toBe(403);
    expect(executadas).toHaveLength(0);
  });

  it("criação usa o colaborador avaliado como alvo e exige capability de criação", async () => {
    const { d, executadas } = deps({ capability: "evaluation.create", scopes: ["ORGANIZATION"] });

    const negado = await avaliacoes(
      requisicao({
        organization_id: ORG,
        operacao: "evaluation.criar",
        alvo: { type: "collaborator", id: AVALIADO },
        cycle_id: CICLO,
      }),
      d
    );
    // `evaluation.create` com escopo ORGANIZATION alcança o tenant ⇒ ALLOW.
    expect(negado.status).toBe(200);
    expect(executadas).toHaveLength(1);
    expect(executadas[0]!.cycleId).toBe(CICLO);
  });
});
