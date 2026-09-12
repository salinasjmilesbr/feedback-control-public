import { describe, expect, it, vi } from "vitest";
import {
  colaboradores,
  type DepsColaboradores,
} from "../../supabase/functions/colaboradores/core.ts";
import {
  ID_NEUTRO,
  type CodigoPublico,
} from "../infrastructure/supabase/colaboradores/contrato.ts";

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
 *
 * Tipagem: os mocks são anotados com os tipos DERIVADOS das próprias deps
 * (`Parameters<...>`), de modo que `mock.calls` seja uma tupla real — nenhuma
 * asserção precisa de cast de array para tupla.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const CALLER = "77777777-7777-4777-8777-777777777777";
const ATOR_COLLAB = "33333333-3333-4333-8333-333333333333";
const ALVO_EXISTENTE = "44444444-4444-4444-8444-444444444444";
const TERCEIRO = "55555555-5555-4555-8555-555555555555";
const NOVO_COLLAB = "66666666-6666-4666-8666-666666666666";
const OPERATION_ID = "88888888-8888-4888-8888-888888888888";

/** Tipos das entradas observadas — derivados das deps do núcleo (sem drift). */
type EntradaGate = Parameters<DepsColaboradores["avaliarAutorizacao"]>[0];
type EntradaMatricula = Parameters<DepsColaboradores["resolverMatricula"]>[0];
type ExecucaoRpc = Parameters<DepsColaboradores["executarRpc"]>[0];
type ContextoRpc = Parameters<DepsColaboradores["executarRpc"]>[1];
type ResultadoRpc = Awaited<ReturnType<DepsColaboradores["executarRpc"]>>;

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
  readonly gateCode?: CodigoPublico;
  readonly matriculaResolvida?: string | null;
  readonly rpcData?: unknown;
  /** Erro devolvido pela RPC (taxonomia F5_08/P2) — para os testes de erro. */
  readonly rpcError?: { readonly code?: string; readonly message?: string } | null;
  /** Capabilities efetivas do ator (plano administrativo). */
  readonly capabilities?: readonly { readonly capability_code: string }[];
}

function montarDeps(cenario: Cenario = {}) {
  /** Ordem observada das etapas — prova que a RPC só ocorre DEPOIS do ALLOW. */
  const ordem: string[] = [];

  const resolverMatricula = vi.fn(
    async (entrada: EntradaMatricula): Promise<string | null> => {
      void entrada;
      ordem.push("matricula");
      return cenario.matriculaResolvida === undefined
        ? ALVO_EXISTENTE
        : cenario.matriculaResolvida;
    }
  );

  const resolverColaboradorVinculado = vi.fn(
    async (authUserId: string, organizationId: string): Promise<string | null> => {
      void authUserId;
      void organizationId;
      ordem.push("vinculo");
      return cenario.vinculado === undefined ? ATOR_COLLAB : cenario.vinculado;
    }
  );

  const avaliarAutorizacao = vi.fn(
    async (
      entrada: EntradaGate
    ): Promise<{ readonly permitido: boolean; readonly code?: CodigoPublico }> => {
      void entrada;
      ordem.push("gate");
      return {
        permitido: cenario.allowed !== false,
        ...(cenario.gateCode ? { code: cenario.gateCode } : {}),
      };
    }
  );

  const executarRpc = vi.fn(
    async (execucao: ExecucaoRpc, contexto: ContextoRpc): Promise<ResultadoRpc> => {
      void execucao;
      void contexto;
      ordem.push("rpc");
      if (cenario.rpcError) return { error: cenario.rpcError };
      return { data: cenario.rpcData ?? NOVO_COLLAB, error: null };
    }
  );

  const d: DepsColaboradores = {
    resolveCaller: async () =>
      cenario.caller === undefined ? CALLER : cenario.caller,
    resolverOrganizacoesDoAtor: async () => cenario.organizacoes ?? [ORG],
    colaboradorPertenceAoAtor: async () => true,
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
    const execucao = executarRpc.mock.calls[0]![0];
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
    const entrada = avaliarAutorizacao.mock.calls[0]![0];
    expect(entrada.operacao).toBe("collaborator.criar");
    expect(entrada.organizationId).toBe(ORG);
    expect(entrada.alvo).toEqual({ type: "collaborator", id: ATOR_COLLAB });
  });

  it("NUNCA usa ID_NEUTRO como alvo da decisão", async () => {
    const { d, avaliarAutorizacao } = montarDeps();

    await colaboradores(requisicao(corpoCriar), d);

    const alvos = avaliarAutorizacao.mock.calls.map(
      ([entrada]) => entrada.alvo.id
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

    const entrada = avaliarAutorizacao.mock.calls[0]![0];
    expect(entrada.alvo.id).toBe(ATOR_COLLAB);
    expect(entrada.alvo.id).not.toBe(TERCEIRO);
    const execucao = executarRpc.mock.calls[0]![0];
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
    const entrada = avaliarAutorizacao.mock.calls[0]![0];
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
    const entrada = avaliarAutorizacao.mock.calls[0]![0];
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

describe("F5-08 P3 — plano administrativo (D19) das operações de estrutura/catálogo", () => {
  const UNIDADE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const CARGO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
  const VALID_FROM = "2026-04-01T00:00:00.000Z";

  const corpoUnidadeCriar = {
    organization_id: ORG,
    operacao: "estrutura.unidade.criar",
    operationId: OPERATION_ID,
    nome: "Unidade Nova",
    validFrom: VALID_FROM,
    motivo: "criacao de unidade",
  };

  const corpoCargoCriar = {
    organization_id: ORG,
    operacao: "catalogo.cargo.criar",
    operationId: OPERATION_ID,
    nome: "Cargo Novo",
    code: "CARGO_NOVO",
    motivo: "criacao de cargo",
  };

  const corpoPosicaoCriar = {
    organization_id: ORG,
    operacao: "estrutura.posicao.criar",
    operationId: OPERATION_ID,
    unidadeId: UNIDADE,
    jobRoleId: CARGO,
    seniorityLevelId: null,
    validFrom: VALID_FROM,
    motivo: "criacao de posicao",
  };

  it("executa a RPC com a capability org.structure.manage e o contexto SOBERANO", async () => {
    const { d, executarRpc } = montarDeps({
      capabilities: [{ capability_code: "org.structure.manage" }],
    });

    const resposta = await colaboradores(requisicao(corpoUnidadeCriar), d);

    expect(resposta.status).toBe(200);
    const corpo = (await resposta.json()) as { ok: boolean; operacao: string };
    expect(corpo.ok).toBe(true);
    expect(corpo.operacao).toBe("estrutura.unidade.criar");
    expect(executarRpc).toHaveBeenCalledTimes(1);

    const [execucao, contexto] = executarRpc.mock.calls[0]!;
    expect(execucao.operacao).toBe("estrutura.unidade.criar");
    // Ator e organização vêm do CONTEXTO revalidado, nunca do corpo.
    expect(contexto.actorUserProfileId).toBe(CALLER);
    expect(contexto.organizationId).toBe(ORG);
  });

  it("NEGA sem a capability de estrutura e não toca a RPC", async () => {
    const { d, executarRpc } = montarDeps({
      capabilities: [{ capability_code: "org.catalog.manage" }],
    });

    const resposta = await colaboradores(requisicao(corpoUnidadeCriar), d);

    expect(resposta.status).toBe(403);
    const corpo = (await resposta.json()) as { error: { code: string } };
    expect(corpo.error.code).toBe("FORBIDDEN");
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("catalog.manage NÃO substitui structure.manage (e vice-versa)", async () => {
    const soEstrutura = montarDeps({
      capabilities: [{ capability_code: "org.structure.manage" }],
    });
    const respostaCargo = await colaboradores(requisicao(corpoCargoCriar), soEstrutura.d);
    expect(respostaCargo.status).toBe(403);
    expect(soEstrutura.executarRpc).not.toHaveBeenCalled();

    const soCatalogo = montarDeps({
      capabilities: [{ capability_code: "org.catalog.manage" }],
    });
    const respostaUnidade = await colaboradores(requisicao(corpoUnidadeCriar), soCatalogo.d);
    expect(respostaUnidade.status).toBe(403);
    expect(soCatalogo.executarRpc).not.toHaveBeenCalled();
  });

  it("permite catálogo com org.catalog.manage", async () => {
    const { d, executarRpc } = montarDeps({
      capabilities: [{ capability_code: "org.catalog.manage" }],
      rpcData: CARGO,
    });

    const resposta = await colaboradores(requisicao(corpoCargoCriar), d);

    expect(resposta.status).toBe(200);
    const corpo = (await resposta.json()) as { ok: boolean; resultado: unknown };
    expect(corpo.ok).toBe(true);
    expect(corpo.resultado).toBe(CARGO);
    expect(executarRpc).toHaveBeenCalledTimes(1);
  });

  it("leva os nullable e o valorVersion validados até a RPC", async () => {
    const { d, executarRpc } = montarDeps({
      capabilities: [{ capability_code: "org.structure.manage" }],
    });

    await colaboradores(requisicao(corpoPosicaoCriar), d);

    const execucao = executarRpc.mock.calls[0]![0];
    expect(execucao.operacao).toBe("estrutura.posicao.criar");
    if (execucao.operacao !== "estrutura.posicao.criar") return;
    expect(execucao.entrada.seniorityLevelId).toBeNull();
    expect(execucao.entrada.unidadeId).toBe(UNIDADE);
  });

  it("aceita lista vazia de membros do colegiado", async () => {
    const { d, executarRpc } = montarDeps({
      capabilities: [{ capability_code: "org.structure.manage" }],
    });

    const resposta = await colaboradores(
      requisicao({
        organization_id: ORG,
        operacao: "estrutura.colegiado.definir",
        operationId: OPERATION_ID,
        collaboratorId: ATOR_COLLAB,
        memberCollaboratorIds: [],
        validFrom: VALID_FROM,
        motivo: "sem colegiado",
      }),
      d
    );

    expect(resposta.status).toBe(200);
    const execucao = executarRpc.mock.calls[0]![0];
    expect(execucao.operacao).toBe("estrutura.colegiado.definir");
    if (execucao.operacao !== "estrutura.colegiado.definir") return;
    expect(execucao.entrada.memberCollaboratorIds).toEqual([]);
  });

  it("aceita colegiado com mais de 200 membros (nenhum teto na Edge)", async () => {
    const { d, executarRpc } = montarDeps({
      capabilities: [{ capability_code: "org.structure.manage" }],
    });
    const muitos = Array.from(
      { length: 250 },
      (_, indice) => "00000000-0000-4000-8000-" + String(indice).padStart(12, "0")
    );

    const resposta = await colaboradores(
      requisicao({
        organization_id: ORG,
        operacao: "estrutura.colegiado.definir",
        operationId: OPERATION_ID,
        collaboratorId: ATOR_COLLAB,
        memberCollaboratorIds: muitos,
        validFrom: VALID_FROM,
        motivo: "colegiado grande",
      }),
      d
    );

    expect(resposta.status).toBe(200);
    expect(executarRpc).toHaveBeenCalledTimes(1);
    const execucao = executarRpc.mock.calls[0]![0];
    expect(execucao.operacao).toBe("estrutura.colegiado.definir");
    if (execucao.operacao !== "estrutura.colegiado.definir") return;
    expect(execucao.entrada.memberCollaboratorIds).toHaveLength(250);
  });

  it("nega operação de OUTRA organização do payload (tenant é revalidado)", async () => {
    const { d, executarRpc } = montarDeps({
      capabilities: [{ capability_code: "org.structure.manage" }],
      organizacoes: [ORG],
    });

    const resposta = await colaboradores(
      requisicao({ ...corpoUnidadeCriar, organization_id: ORG_B }),
      d
    );

    expect(resposta.status).toBe(403);
    expect(executarRpc).not.toHaveBeenCalled();
  });

  it("recusa identidade declarada no corpo (nunca substitui o JWT)", async () => {
    for (const campo of ["actor_user_profile_id", "actor_id", "ator", "capability"]) {
      const { d, executarRpc } = montarDeps({
        capabilities: [{ capability_code: "org.structure.manage" }],
      });
      const resposta = await colaboradores(
        requisicao({ ...corpoUnidadeCriar, [campo]: CALLER }),
        d
      );
      expect(resposta.status, campo).toBe(400);
      expect(executarRpc, campo).not.toHaveBeenCalled();
    }
  });

  it("operação desconhecida é fail-closed: 400 e nenhuma RPC", async () => {
    const { d, executarRpc } = montarDeps({
      capabilities: [{ capability_code: "org.structure.manage" }],
    });

    const resposta = await colaboradores(
      requisicao({ ...corpoUnidadeCriar, operacao: "estrutura.unidade.apagar" }),
      d
    );

    expect(resposta.status).toBe(400);
    const corpo = (await resposta.json()) as { error: { code: string } };
    expect(corpo.error.code).toBe("INVALID_INPUT");
    expect(executarRpc).not.toHaveBeenCalled();
  });
});

describe("F5-08 P3 — taxonomia de erro das RPCs (F5_08_*) sem vazamento interno", () => {
  const corpo = {
    organization_id: ORG,
    operacao: "estrutura.unidade.criar",
    operationId: OPERATION_ID,
    nome: "Unidade Nova",
    validFrom: "2026-04-01T00:00:00.000Z",
    motivo: "criacao de unidade",
  };

  async function responderCom(rpcError: { code?: string; message?: string }) {
    const { d } = montarDeps({
      capabilities: [{ capability_code: "org.structure.manage" }],
      rpcError,
    });
    const resposta = await colaboradores(requisicao(corpo), d);
    const json = (await resposta.json()) as { error: { code: string; message: string } };
    return { status: resposta.status, json };
  }

  it.each([
    ["F5_08_INVALID_INPUT", 400, "INVALID_INPUT"],
    ["F5_08_FORBIDDEN", 403, "FORBIDDEN"],
    ["F5_08_NOT_FOUND", 404, "NOT_FOUND"],
    ["F5_08_CONFLICT", 409, "CONFLICT"],
  ])("mapeia %s para %i (%s)", async (prefixo, status, codigo) => {
    const { status: obtido, json } = await responderCom({
      code: "P0001",
      message: `${prefixo}: detalhe interno do banco`,
    });

    expect(obtido).toBe(status);
    expect(json.error.code).toBe(codigo);
    // Nenhum vazamento do detalhe SQL/constraint.
    expect(json.error.message).not.toContain(prefixo);
    expect(json.error.message).not.toContain("detalhe interno");
  });

  it("erro DESCONHECIDO é fail-closed (500 INTERNAL) e não vaza SQL", async () => {
    const { status, json } = await responderCom({
      code: "XX000",
      message:
        'relation "public.structure_helpers" does not exist at character 42 (SQLSTATE XX000)',
    });

    expect(status).toBe(500);
    expect(json.error.code).toBe("INTERNAL");
    expect(json.error.message).not.toContain("structure_helpers");
    expect(json.error.message).not.toContain("SQLSTATE");
  });

  it("violação de integridade do banco (23xxx) continua CONFLICT, sem vazar constraint", async () => {
    const { status, json } = await responderCom({
      code: "23P01",
      message: 'conflicting key value violates exclusion constraint "ex_organizational_unit_parent_periods_no_overlap"',
    });

    expect(status).toBe(409);
    expect(json.error.code).toBe("CONFLICT");
    expect(json.error.message).not.toContain("ex_organizational_unit_parent_periods_no_overlap");
  });
});
