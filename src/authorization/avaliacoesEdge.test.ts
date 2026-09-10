import { describe, expect, it, vi } from "vitest";
import {
  avaliacoes,
  type DepsAvaliacoes,
  type ExecucaoAvaliacao,
} from "../../supabase/functions/avaliacoes/core.ts";
import {
  CAPABILITY_POR_OPERACAO,
  ehOperacaoAvaliacao,
  validarEntradaAvaliacao,
} from "../infrastructure/supabase/avaliacoes/contrato.ts";

const ORG = "11111111-1111-4111-8111-111111111111";
const AVALIACAO = "22222222-2222-4222-8222-222222222222";
const COLABORADOR = "33333333-3333-4333-8333-333333333333";
const PARTICIPANTE = "44444444-4444-4444-8444-444444444444";
const CICLO = "55555555-5555-4555-8555-555555555555";
const SUB = "66666666-6666-4666-8666-666666666666";
const CALLER = "77777777-7777-4777-8777-777777777777";

function requisicao(corpo: unknown, headers: Record<string, string> = {}): Request {
  return new Request("http://localhost/functions/v1/avaliacoes", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(corpo),
  });
}

interface Cenario {
  readonly allowed?: boolean;
  readonly code?: string;
  readonly caller?: string | null;
  readonly rpcError?: { code?: string; message?: string } | null;
  readonly rpcData?: unknown;
  /** Resultado da ponte matrícula → UUID (`null` força a recusa). */
  readonly matriculaResolvida?: string | null;
}

function deps(cenario: Cenario = {}) {
  const executarRpc = vi.fn(async (execucao: ExecucaoAvaliacao) => ({
    data: cenario.rpcData ?? execucao.evaluationId,
    error: cenario.rpcError ?? null,
  }));
  const avaliarAutorizacao = vi.fn(async () => ({
    allowed: cenario.allowed !== false,
    ...(cenario.code ? { code: cenario.code as never } : {}),
  }));
  const d: DepsAvaliacoes = {
    resolveCaller: async () =>
      cenario.caller === undefined ? CALLER : cenario.caller,
    avaliarAutorizacao,
    executarRpc,
    // Ponte matrícula → UUID na fronteira (o alvo autorizável é o UUID).
    resolverMatricula: async () =>
      cenario.matriculaResolvida === undefined ? COLABORADOR : cenario.matriculaResolvida,
  };
  return { d, executarRpc, avaliarAutorizacao };
}

const corpoValido = {
  organization_id: ORG,
  operacao: "evaluation.gravar_notas",
  alvo: { type: "evaluation", id: AVALIACAO },
  notas: [{ subcriterion_id: SUB, nota: 4 }],
};

describe("contrato Ã— operaÃ§Ãµes (F5-06 Â§8.3)", () => {
  it("mapeia cada operaÃ§Ã£o para uma capability EXISTENTE do catÃ¡logo (sem capability nova)", () => {
    const codigos = Object.values(CAPABILITY_POR_OPERACAO);
    expect(new Set(codigos)).toEqual(
      new Set([
        "evaluation.create",
        "evaluation.read",
        "evaluation.write",
        "evaluation.reopen",
        "evaluation.cancel",
      ])
    );
    // D18: conclusÃ£o NÃƒO cria capability nova.
    expect(codigos).not.toContain("evaluation.complete");
  });

  it("reconhece somente operaÃ§Ãµes declaradas", () => {
    expect(ehOperacaoAvaliacao("evaluation.concluir")).toBe(true);
    expect(ehOperacaoAvaliacao("evaluation.importar")).toBe(false);
  });
});

describe("validaÃ§Ã£o da intenÃ§Ã£o (nunca da autoridade)", () => {
  it("recusa actor_id no corpo (identidade nunca vem do cliente)", () => {
    const r = validarEntradaAvaliacao({ ...corpoValido, actor_id: CALLER });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("INVALID_INPUT");
  });

  it("exige UUID em organization_id, alvo e subcritÃ©rio", () => {
    expect(validarEntradaAvaliacao({ ...corpoValido, organization_id: "matricula-123" }).ok).toBe(
      false
    );
    expect(
      validarEntradaAvaliacao({
        ...corpoValido,
        alvo: { type: "evaluation", id: "1" },
      }).ok
    ).toBe(false);
    expect(
      validarEntradaAvaliacao({
        ...corpoValido,
        notas: [{ subcriterion_id: "abc", nota: 4 }],
      }).ok
    ).toBe(false);
  });

  it("exige alvo do tipo correto por operaÃ§Ã£o (criaÃ§Ã£o usa o colaborador avaliado)", () => {
    const criacao = {
      organization_id: ORG,
      operacao: "evaluation.criar",
      alvo: { type: "collaborator", id: COLABORADOR },
      cycle_id: CICLO,
    };
    expect(validarEntradaAvaliacao(criacao).ok).toBe(true);
    expect(
      validarEntradaAvaliacao({ ...criacao, alvo: { type: "evaluation", id: AVALIACAO } }).ok
    ).toBe(false);
  });

  it("recusa nota fora de 1..5 e nÃ£o inteira", () => {
    for (const nota of [0, 6, 3.5, -1]) {
      const r = validarEntradaAvaliacao({
        ...corpoValido,
        notas: [{ subcriterion_id: SUB, nota }],
      });
      expect(r.ok).toBe(false);
    }
  });
});

describe("fronteira confiÃ¡vel do caminho novo", () => {
  it("sem header Authorization â‡’ 401 e o engine NÃƒO Ã© consultado", async () => {
    const { d, avaliarAutorizacao } = deps();
    const resposta = await avaliacoes(
      new Request("http://localhost/functions/v1/avaliacoes", {
        method: "POST",
        body: JSON.stringify(corpoValido),
      }),
      d
    );
    expect(resposta.status).toBe(401);
    expect(avaliarAutorizacao).not.toHaveBeenCalled();
  });

  it("JWT invÃ¡lido (resolveCaller nulo) â‡’ 401", async () => {
    const { d, executarRpc } = deps({ caller: null });
    const resposta = await avaliacoes(
      requisicao(corpoValido, { Authorization: "Bearer invalido" }),
      d
    );
    expect(resposta.status).toBe(401);
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("corpo forjado â‡’ 400 e a RPC NÃƒO Ã© executada", async () => {
    const { d, executarRpc } = deps();
    const resposta = await avaliacoes(
      requisicao({ ...corpoValido, actor_user_profile_id: CALLER }, { Authorization: "Bearer ok" }),
      d
    );
    expect(resposta.status).toBe(400);
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("DENY do Policy Engine â‡’ 403 e a RPC NÃƒO Ã© executada (sem bypass por service_role)", async () => {
    const { d, executarRpc } = deps({ allowed: false, code: "FORBIDDEN" });
    const resposta = await avaliacoes(
      requisicao(corpoValido, { Authorization: "Bearer ok" }),
      d
    );
    expect(resposta.status).toBe(403);
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("cross-tenant (NOT_FOUND pÃºblico) â‡’ 404", async () => {
    const { d } = deps({ allowed: false, code: "NOT_FOUND" });
    const resposta = await avaliacoes(
      requisicao(corpoValido, { Authorization: "Bearer ok" }),
      d
    );
    expect(resposta.status).toBe(404);
    const corpo = (await resposta.json()) as { error: { code: string } };
    expect(corpo.error.code).toBe("NOT_FOUND");
  });

  it("domÃ­nio recusa (reabertura etc.) â‡’ 409 sem vazar mensagem interna", async () => {
    const { d } = deps({
      rpcError: { code: "P0001", message: "F5-06: avaliacao ja concluida (interno)" },
    });
    const resposta = await avaliacoes(
      requisicao(
        {
          organization_id: ORG,
          operacao: "evaluation.reabrir",
          alvo: { type: "evaluation", id: AVALIACAO },
          motivo: "Reabertura sintetica",
        },
        { Authorization: "Bearer ok" }
      ),
      d
    );
    expect(resposta.status).toBe(409);
    const texto = JSON.stringify(await resposta.json());
    expect(texto).not.toContain("interno");
  });

  it("ALLOW â‡’ executa a RPC com o ator VERIFICADO (nunca o corpo) e o alvo real", async () => {
    const { d, executarRpc } = deps({ rpcData: 3.5 });
    const resposta = await avaliacoes(
      requisicao(corpoValido, { Authorization: "Bearer ok" }),
      d
    );
    expect(resposta.status).toBe(200);
    expect(executarRpc).toHaveBeenCalledTimes(1);
    const execucao = executarRpc.mock.calls[0]![0];
    expect(execucao.actorUserProfileId).toBe(CALLER);
    expect(execucao.organizationId).toBe(ORG);
    expect(execucao.evaluationId).toBe(AVALIACAO);
    expect(execucao.notas).toHaveLength(1);
    // CORREÇÃO DE AUDITORIA (IDOR): nenhuma ocorrência atravessa a execução —
    // ela é resolvida dentro da RPC a partir do ator verificado.
    expect("participantId" in execucao).toBe(false);
  });

  it("participant_id no payload é RECUSADO (a ocorrência é resolvida no servidor)", async () => {
    const { d, executarRpc } = deps();
    const resposta = await avaliacoes(
      requisicao(
        { ...corpoValido, participant_id: PARTICIPANTE },
        { Authorization: "Bearer ok" }
      ),
      d
    );

    expect(resposta.status).toBe(400);
    const corpo = (await resposta.json()) as { error: { code: string } };
    expect(corpo.error.code).toBe("INVALID_INPUT");
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("matrícula do avaliado é encaminhada como INTENÇÃO (ponte resolvida no Edge)", async () => {
    const { d, executarRpc } = deps({ rpcData: AVALIACAO });
    const resposta = await avaliacoes(
      requisicao(
        {
          organization_id: ORG,
          operacao: "evaluation.criar",
          alvo: { type: "collaborator", id: COLABORADOR },
          cycle_id: CICLO,
          matricula_avaliado: 101,
        },
        { Authorization: "Bearer ok" }
      ),
      d
    );

    expect(resposta.status).toBe(200);
    const execucao = executarRpc.mock.calls[0]![0];
    expect(execucao.matriculaAvaliado).toBe(101);
    expect(execucao.cycleId).toBe(CICLO);
  });

  it("matrícula inválida no corpo ⇒ 400 e nenhuma execução", async () => {
    const { d, executarRpc } = deps();
    const resposta = await avaliacoes(
      requisicao(
        {
          organization_id: ORG,
          operacao: "evaluation.criar",
          alvo: { type: "collaborator", id: COLABORADOR },
          cycle_id: CICLO,
          matricula_avaliado: "abc",
        },
        { Authorization: "Bearer ok" }
      ),
      d
    );

    expect(resposta.status).toBe(400);
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("método não permitido ⇒ 405", async () => {
    const { d } = deps();
    const resposta = await avaliacoes(
      new Request("http://localhost/functions/v1/avaliacoes", { method: "GET" }),
      d
    );
    expect(resposta.status).toBe(405);
  });
});
