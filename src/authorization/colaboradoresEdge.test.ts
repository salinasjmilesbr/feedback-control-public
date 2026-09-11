import { describe, expect, it, vi } from "vitest";
import {
  colaboradores,
  type DepsColaboradores,
  type OperacaoExecutavel,
} from "../../supabase/functions/colaboradores/core.ts";
import { ID_NEUTRO } from "../infrastructure/supabase/colaboradores/contrato.ts";

/**
 * F5-07 — BLOCKER da auditoria do PR #181: `collaborator.criar` não pode ser
 * estruturalmente impossível.
 *
 * Causa corrigida: (1) a matrícula da CRIAÇÃO é DADO a criar, não identidade a
 * resolver — resolvê-la devolvia `null` e a operação terminava em `NOT_FOUND`
 * antes do gate; (2) o alvo da decisão caía em `ID_NEUTRO`, que não é recurso
 * soberano, e o ResourceContext de `collaborator` não podia ser carregado.
 *
 * Contrato preservado: `collaborator.create` continua no PLANO FUNCIONAL, com a
 * capability `collaborator.create`, gateada pelo Policy Engine antes da RPC; a
 * âncora autorizável é o colaborador VINCULADO do ator (F5-02) — recurso REAL do
 * tenant, resolvido server-side. Sem vínculo, sem tenant válido, sem capability
 * ou com membership revogada ⇒ fail-closed, sem recurso fictício e sem tocar a
 * RPC. `service_role` continua apenas executor.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const CALLER = "77777777-7777-4777-8777-777777777777";
const ATOR_COLLAB = "33333333-3333-4333-8333-333333333333";
const ALVO_EXISTENTE = "44444444-4444-4444-8444-444444444444";
const TERCEIRO = "55555555-5555-4555-8555-555555555555";
const NOVO_COLLAB = "66666666-6666-4666-8666-666666666666";
const OPERATION_ID = "88888888-8888-4888-8888-888888888888";

function requisicao(corpo: unknown, headers: Record<string, string> = {}): Request {
  return new Request("http://localhost/functions/v1/colaboradores", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer token",
      ...headers,
    },
    body: JSON.stringify(corpo),
  });
}

interface Cenario {
  readonly caller?: string | null;
  readonly organizacoes?: readonly string[];
  readonly vinculado?: string | null;
  readonly allowed?: boolean;
  readonly gateCode?: string;
  readonly matriculaResolvida?: string | null;
  readonly pertence?: boolean;
  readonly rpcData?: unknown;
  readonly rpcError?: { code?: string; message?: string } | null;
  /** Capabilities efetivas do ator (plano administrativo). */
  readonly capabilities?: readonly { readonly capability_code: string }[];
}

function montarDeps(cenario: Cenario = {}) {
  /** Ordem observada das etapas — prova que a RPC só occurs DEPOIS do ALLOW. */
  const ordem: string[] = [];
  const resolverMatricula = vi.fn(async () => {
    ordem.push("matricula");
    return cenario.matriculaResolvida === undefined
      ? ALVO_EXISTENTE
      : cenario.matriculaResolvida;
  });
  const resolverColaboradorVinculado = vi.fn(async () => {
    ordem.push("vinculo");
    return cenario.vinculado === undefined ? ATOR_COLLAB : cenario.vinculado;
  });
  const avaliarAutorizacao = vi.fn(
    async () => {
      ordem.push("gate");
      return {
        permitido: cenario.allowed !== false,
        ...(cenario.gateCode ? { code: cenario.gateCode as never } : {}),
      };
    }
  );
  const executarRpc = vi.fn(async () => {
    ordem.push("rpc");
    return { data: cenario.rpcData ?? NOVO_COLLAB, error: cenario.rpcError ?? null };
  });

  const d: DepsColaboradores = {
    resolveCaller: async () =>
      cenario.caller === undefined ? CALLER : cenario.caller,
    resolverOrganizacoesDoAtor: async () => cenario.organizacoes ?? [ORG],
    colaboradorPertenceAoAtor: async () => cenario.pertence !== false,
    resolverMatricula,
    resolverColaboradorVinculado,
    avaliarAutorizacao,
    resolverCapabilitiesEfetivas: async () => cenario.capabilities ?? [],
    executarRpc,
  };
  return {
    d,
    ordem,
    resolverMatricula,
    resolverColaboradorVinculado,
    avaliarAutorizacao,
    executarRpc,
  };
}

const corpoCriar = {
  organization_id: ORG,
  operacao: "collaborator.criar",
  operation_id: OPERATION_ID,
  full_name: "Pessoa Fictícia da Silva",
  email: "pessoa.ficticia@example.com",
  matricula: "100999",
};

describe("F5-07 — collaborator.criar: matrícula é DADO, não identidade", () => {
  it("NÃO resolve a matrícula da criação (ela ainda não existe)", async () => {
    const { d, resolverMatricula } = montarDeps();

    const resposta = await colaboradores(requisicao(corpoCriar), d);

    expect(resposta.status).toBe(200);
    expect(resolverMatricula).not.toHaveBeenCalled();
  });

  it("NÃO devolve NOT_FOUND por matrícula inexistente (não há resolução)", async () => {
    const { d } = montarDeps({ matriculaResolvida: null });

    const resposta = await colaboradores(requisicao(corpoCriar), d);

    expect(resposta.status).toBe(200);
    const corpo = (await resposta.json()) as { ok: boolean };
    expect(corpo.ok).toBe(true);
  });

  it("leva a matrícula nova até a RPC apenas como DADO de criação", async () => {
    const { d, executarRpc } = montarDeps();

    await colaboradores(requisicao(corpoCriar), d);

    expect(executarRpc).toHaveBeenCalledTimes(1);
    const [execucao] = executarRpc.mock.calls[0] as [OperacaoExecutavel];
    expect(execucao.operacao).toBe("collaborator.criar");
    if (execucao.operacao !== "collaborator.criar") return;
    expect(execucao.entrada.matricula).toBe("100999");
    expect(execucao.entrada).not.toHaveProperty("collaborator_id");
  });
});

describe("F5-07 — collaborator.criar: âncora soberana do ator (sem recurso fictício)", () => {
  it("usa a capability collaborator.create com o colaborador VINCULADO do ator", async () => {
    const { d, avaliarAutorizacao, resolverColaboradorVinculado } = montarDeps();

    const resposta = await colaboradores(requisicao(corpoCriar), d);

    expect(resposta.status).toBe(200);
    expect(resolverColaboradorVinculado).toHaveBeenCalledWith(CALLER, ORG);
    expect(avaliarAutorizacao).toHaveBeenCalledTimes(1);
    const [entrada] = avaliarAutorizacao.mock.calls[0] as [
      { operacao: string; alvo: { type: string; id: string }; organizationId: string },
    ];
    expect(entrada.operacao).toBe("collaborator.criar");
    expect(entrada.organizationId).toBe(ORG);
    expect(entrada.alvo).toEqual({ type: "collaborator", id: ATOR_COLLAB });
  });

  it("NUNCA usa ID_NEUTRO como alvo da decisão", async () => {
    const { d, avaliarAutorizacao } = montarDeps();

    await colaboradores(requisicao(corpoCriar), d);

    const alvos = avaliarAutorizacao.mock.calls.map(
      ([entrada]) => (entrada as { alvo: { id: string } }).alvo.id
    );
    expect(alvos).not.toContain(ID_NEUTRO);
  });

  it("ator SEM vínculo (F5-02) é fail-closed: nega e não toca a RPC", async () => {
    const { d, avaliarAutorizacao, executarRpc } = montarDeps({ vinculado: null });

    const resposta = await colaboradores(requisicao(corpoCriar), d);

    expect(resposta.status).toBe(403);
    const corpo = (await resposta.json()) as { error: { code: string } };
    expect(corpo.error.code).toBe("FORBIDDEN");
    expect(avaliarAutorizacao).not.toHaveBeenCalled();
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("ignora `collaborator_id` informado pelo cliente na criação", async () => {
    const { d, avaliarAutorizacao, executarRpc } = montarDeps();

    await colaboradores(
      requisicao({ ...corpoCriar, collaborator_id: TERCEIRO }),
      d
    );

    const [entrada] = avaliarAutorizacao.mock.calls[0] as [
      { alvo: { id: string } },
    ];
    expect(entrada.alvo.id).toBe(ATOR_COLLAB);
    expect(entrada.alvo.id).not.toBe(TERCEIRO);
    const [execucao] = executarRpc.mock.calls[0] as [OperacaoExecutavel];
    expect(execucao.entrada).not.toHaveProperty("collaborator_id");
  });
});

describe("F5-07 — collaborator.criar: negações e ordem do gate", () => {
  it("nega sem a capability (Policy Engine) e não executa a RPC", async () => {
    const { d, executarRpc, ordem } = montarDeps({ allowed: false });

    const resposta = await colaboradores(requisicao(corpoCriar), d);

    expect(resposta.status).toBe(403);
    expect(ordem).toContain("gate");
    expect(ordem).not.toContain("rpc");
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("nega criação em outro tenant (organization_id do payload é intenção)", async () => {
    const { d, avaliarAutorizacao, executarRpc, resolverColaboradorVinculado } =
      montarDeps({ organizacoes: [ORG] });

    const resposta = await colaboradores(
      requisicao({ ...corpoCriar, organization_id: ORG_B }),
      d
    );

    expect(resposta.status).toBe(403);
    expect(resolverColaboradorVinculado).not.toHaveBeenCalled();
    expect(avaliarAutorizacao).not.toHaveBeenCalled();
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("nega após revogação de membership (sem cache entre requests)", async () => {
    const { d, executarRpc } = montarDeps({ organizacoes: [] });

    const resposta = await colaboradores(requisicao(corpoCriar), d);

    expect(resposta.status).toBe(403);
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("executa a RPC SOMENTE depois do ALLOW", async () => {
    const { d, ordem } = montarDeps();

    await colaboradores(requisicao(corpoCriar), d);

    expect(ordem.indexOf("gate")).toBeGreaterThanOrEqual(0);
    expect(ordem.indexOf("gate")).toBeLessThan(ordem.indexOf("rpc"));
  });
});

describe("F5-07 — regressões das demais operações", () => {
  it("collaborator.obter por matrícula continua resolvendo a INTENÇÃO para UUID", async () => {
    const { d, resolverMatricula, avaliarAutorizacao, executarRpc } = montarDeps({
      rpcData: { id: ALVO_EXISTENTE, full_name: "Pessoa" },
    });

    const resposta = await colaboradores(
      requisicao({
        organization_id: ORG,
        operacao: "collaborator.obter",
        matricula: "100001",
      }),
      d
    );

    expect(resposta.status).toBe(200);
    expect(resolverMatricula).toHaveBeenCalledTimes(1);
    const [entrada] = avaliarAutorizacao.mock.calls[0] as [
      { operacao: string; alvo: { id: string } },
    ];
    expect(entrada.alvo.id).toBe(ALVO_EXISTENTE);
    expect(executarRpc).toHaveBeenCalledTimes(1);
  });

  it("collaborator.obter com matrícula ambígua/ausente devolve NOT_FOUND", async () => {
    const { d, executarRpc } = montarDeps({ matriculaResolvida: null });

    const resposta = await colaboradores(
      requisicao({
        organization_id: ORG,
        operacao: "collaborator.obter",
        matricula: "100001",
      }),
      d
    );

    expect(resposta.status).toBe(404);
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("collaborator.listar usa a âncora do ator (nunca ID_NEUTRO)", async () => {
    const { d, avaliarAutorizacao, resolverMatricula } = montarDeps({
      rpcData: [],
    });

    const resposta = await colaboradores(
      requisicao({ organization_id: ORG, operacao: "collaborator.listar" }),
      d
    );

    expect(resposta.status).toBe(200);
    expect(resolverMatricula).not.toHaveBeenCalled();
    const [entrada] = avaliarAutorizacao.mock.calls[0] as [
      { alvo: { type: string; id: string } },
    ];
    expect(entrada.alvo).toEqual({ type: "collaborator", id: ATOR_COLLAB });
  });

  it("colaborador.ocupacao.definir continua no PLANO ADMINISTRATIVO", async () => {
    const { d, avaliarAutorizacao, resolverColaboradorVinculado, executarRpc } =
      montarDeps({
        rpcData: NOVO_COLLAB,
        capabilities: [{ capability_code: "org.structure.manage" }],
      });

    const resposta = await colaboradores(
      requisicao({
        organization_id: ORG,
        operacao: "colaborador.ocupacao.definir",
        operation_id: OPERATION_ID,
        collaborator_id: TERCEIRO,
        position_id: ALVO_EXISTENTE,
        vigencia: "2025-01-01T00:00:00Z",
        motivo: "Alocação sintética",
      }),
      d
    );

    expect(resposta.status).toBe(200);
    // Plano administrativo NÃO passa pelo engine funcional.
    expect(avaliarAutorizacao).not.toHaveBeenCalled();
    expect(resolverColaboradorVinculado).not.toHaveBeenCalled();
    expect(executarRpc).toHaveBeenCalledTimes(1);
  });
});
