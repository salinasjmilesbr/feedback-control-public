import { describe, expect, it } from "vitest";
import repositorioFonte from "./repositorioMetasSoberanas.ts?raw";
import type {
  AprovacaoRegistradaSoberana,
  EscopoMetasSoberanas,
  GoalRepository,
  LimitesDoSoberanos,
  MetaMutadaSoberana,
  ResultadoMetas,
} from "../../../application/ports/GoalRepository";
import type { EdgeMetas, ResultadoEdgeMetas } from "./edgeMetas";
import { criarRepositorioMetasSoberanas } from "./repositorioMetasSoberanas";

/**
 * F5-10 P5 (Issue #218), Bloco 1/S2 — repositório soberano de metas (D22-A).
 *
 * Prova que o PORT é atendido EXCLUSIVAMENTE pelo adapter da Edge — leitura
 * inclusive (`goal.listar_por_escopo`) —, que nenhuma tabela/RLS é acessada, que
 * a projeção não inventa campos (linha fora do contrato é descartada e envelope
 * anômalo é `INTERNAL`) e que os erros propagam como `Resultado*` fail-closed.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const OUTRA_ORG = "99999999-9999-4999-8999-999999999999";
const META = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const META_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const CICLO = "55555555-5555-4555-8555-555555555555";
const OUTRO_CICLO = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const COLABORADOR = "77777777-7777-4777-8777-777777777777";
const APROVACAO = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
const OPERACAO = "66666666-6666-4666-8666-666666666666";

type MetodoEdge =
  | "criar"
  | "editar"
  | "atualizarProgresso"
  | "finalizar"
  | "revisarFinalizacao"
  | "excluir"
  | "aprovar"
  | "definirLimitesDoCiclo"
  | "listarPorEscopo";

interface InvocacaoEdge {
  readonly metodo: MetodoEdge;
  readonly entrada: Record<string, unknown>;
}

interface EdgeFalso {
  readonly edge: EdgeMetas;
  readonly invocacoes: InvocacaoEdge[];
}

const METODOS: readonly MetodoEdge[] = [
  "criar",
  "editar",
  "atualizarProgresso",
  "finalizar",
  "revisarFinalizacao",
  "excluir",
  "aprovar",
  "definirLimitesDoCiclo",
  "listarPorEscopo",
];

function edgeFalso(
  respostas: Partial<Record<MetodoEdge, ResultadoEdgeMetas<unknown>>> = {}
): EdgeFalso {
  const invocacoes: InvocacaoEdge[] = [];
  const responder =
    (metodo: MetodoEdge) =>
    async (entrada: unknown): Promise<ResultadoEdgeMetas<unknown>> => {
      invocacoes.push({ metodo, entrada: entrada as Record<string, unknown> });
      return respostas[metodo] ?? { ok: true, data: {} };
    };

  const edge: EdgeMetas = {
    criar: responder("criar"),
    editar: responder("editar"),
    atualizarProgresso: responder("atualizarProgresso"),
    finalizar: responder("finalizar"),
    revisarFinalizacao: responder("revisarFinalizacao"),
    excluir: responder("excluir"),
    aprovar: responder("aprovar"),
    definirLimitesDoCiclo: responder("definirLimitesDoCiclo"),
    listarPorEscopo: responder("listarPorEscopo"),
  };

  return { edge, invocacoes };
}

/** Remove comentários: as barreiras valem para o CÓDIGO, não para a prosa. */
function apenasCodigo(fonte: string): string {
  return fonte
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((linha) => {
      const indice = linha.indexOf("//");
      return indice === -1 ? linha : linha.slice(0, indice);
    })
    .join("\n");
}

function linhaMeta(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    goal_id: META,
    cycle_id: CICLO,
    collaborator_id: COLABORADOR,
    tipo: "NEGOCIO_PROJETO",
    descricao: "Reduzir retrabalho",
    kpi: "Retrabalho por lote",
    valor_alvo: "<= 2%",
    status: "EM_ANDAMENTO",
    progresso_percentual: 40,
    resultado_atual: "45",
    resultado_final: null,
    atingida: null,
    excluida: false,
    version: 2,
    relacao: "SELF",
    aprovacoes_vigentes: [
      {
        papel: "COORDENADOR",
        aprovacao_id: APROVACAO,
        decidido_em: "2035-02-01T10:00:00.000Z",
        motivo: null,
      },
    ],
    ...extra,
  };
}

/** Envelope REAL de `meta_listar_por_escopo` (P4 §11). */
function envelope(
  metas: readonly unknown[],
  extra: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    organization_id: ORG,
    cycle_id: CICLO,
    ciclo_status: "ATIVO",
    relacao_ator: metas.length === 0 ? "SEM_META_AUTORIZADA" : "ESCOPO_APLICADO",
    quantidade: metas.length,
    metas,
    ...extra,
  };
}

const ENTRADA_BASE = {
  organizationId: ORG,
  goalId: META,
  expectedVersion: 3,
  operationId: OPERACAO,
} as const;

describe("F5-10 P5 — repositório soberano de metas (port atendido pela Edge)", () => {
  it("cada método do port atravessa a operação correspondente do adapter", async () => {
    const { edge, invocacoes } = edgeFalso({
      criar: { ok: true, data: { goal_id: META, version: 0, status: "EM_ANDAMENTO" } },
      editar: { ok: true, data: { goal_id: META, version: 4, status: "EM_ANDAMENTO" } },
      atualizarProgresso: {
        ok: true,
        data: { goal_id: META, version: 5, status: "EM_ANDAMENTO" },
      },
      finalizar: { ok: true, data: { goal_id: META, version: 6, status: "ATINGIDA" } },
      revisarFinalizacao: {
        ok: true,
        data: { goal_id: META, version: 7, status: "NAO_ATINGIDA" },
      },
      excluir: { ok: true, data: { goal_id: META, version: 8, status: "ATINGIDA" } },
      aprovar: {
        ok: true,
        data: {
          goal_id: META,
          aprovacao_id: APROVACAO,
          papel: "COORDENADOR",
          version: 9,
          status: "EM_ANDAMENTO",
          aprovado: true,
        },
      },
      definirLimitesDoCiclo: {
        ok: true,
        data: { cycle_id: CICLO, version: 10, tipo: "INDIVIDUAL", quantidade: 3 },
      },
      listarPorEscopo: { ok: true, data: envelope([linhaMeta()]) },
    });
    const repositorio: GoalRepository = criarRepositorioMetasSoberanas(edge);

    const criada: ResultadoMetas<MetaMutadaSoberana> = await repositorio.criarMeta({
      organizationId: ORG,
      cycleId: CICLO,
      collaboratorId: COLABORADOR,
      tipo: "NEGOCIO_PROJETO",
      descricao: "Reduzir retrabalho",
      kpi: "Retrabalho por lote",
      valorAlvo: "<= 2%",
      operationId: OPERACAO,
    });
    await repositorio.editarMeta({
      ...ENTRADA_BASE,
      descricao: "Nova descricao",
      kpi: "Novo KPI",
      valorAlvo: "100",
    });
    await repositorio.atualizarProgressoMeta({
      ...ENTRADA_BASE,
      resultadoAtual: "50",
      progressoPercentual: 50,
    });
    await repositorio.finalizarMeta({ ...ENTRADA_BASE, resultadoFinal: "100", atingida: true });
    await repositorio.revisarFinalizacaoMeta({
      ...ENTRADA_BASE,
      resultadoFinal: "80",
      atingida: false,
      motivo: "Correcao",
    });
    await repositorio.excluirMeta({ ...ENTRADA_BASE, motivo: "Duplicada" });
    const aprovada: ResultadoMetas<AprovacaoRegistradaSoberana> = await repositorio.aprovarMeta({
      ...ENTRADA_BASE,
      papel: "COORDENADOR",
    });
    const limites: ResultadoMetas<LimitesDoSoberanos> = await repositorio.definirLimitesDoCiclo({
      organizationId: ORG,
      cycleId: CICLO,
      tipo: "INDIVIDUAL",
      quantidade: 3,
      motivo: "Ampliacao",
      expectedVersion: 7,
      operationId: OPERACAO,
    });
    const lida: ResultadoMetas<EscopoMetasSoberanas> = await repositorio.listarMetasPorEscopo(
      ORG,
      CICLO,
      { operationId: OPERACAO }
    );

    expect(invocacoes.map((item) => item.metodo)).toEqual([...METODOS]);

    // A INTENÇÃO chega ao adapter em camelCase (a tradução snake_case é do adapter).
    expect(invocacoes[0]!.entrada).toEqual({
      organizationId: ORG,
      cycleId: CICLO,
      collaboratorId: COLABORADOR,
      tipo: "NEGOCIO_PROJETO",
      descricao: "Reduzir retrabalho",
      kpi: "Retrabalho por lote",
      valorAlvo: "<= 2%",
      operationId: OPERACAO,
    });
    expect(invocacoes[8]!.entrada).toEqual({
      organizationId: ORG,
      cycleId: CICLO,
      operationId: OPERACAO,
    });

    // Projeções: sem campos inventados (o `aprovado` constante da RPC é ignorado).
    expect(criada).toEqual({
      ok: true,
      data: { goalId: META, version: 0, status: "EM_ANDAMENTO" },
    });
    expect(aprovada).toEqual({
      ok: true,
      data: {
        goalId: META,
        aprovacaoId: APROVACAO,
        papel: "COORDENADOR",
        version: 9,
        status: "EM_ANDAMENTO",
      },
    });
    expect(limites).toEqual({
      ok: true,
      data: { cycleId: CICLO, version: 10, tipo: "INDIVIDUAL", quantidade: 3 },
    });
    expect(lida.ok).toBe(true);
  });

  it("a leitura vai por `goal.listar_por_escopo` e projeta o escopo soberano", async () => {
    const { edge, invocacoes } = edgeFalso({
      listarPorEscopo: { ok: true, data: envelope([linhaMeta()]) },
    });
    const resultado = await criarRepositorioMetasSoberanas(edge).listarMetasPorEscopo(
      ORG,
      CICLO,
      { operationId: OPERACAO }
    );

    expect(invocacoes).toHaveLength(1);
    expect(invocacoes[0]!.metodo).toBe("listarPorEscopo");
    expect(invocacoes[0]!.entrada).toEqual({
      organizationId: ORG,
      cycleId: CICLO,
      operationId: OPERACAO,
    });
    expect(resultado).toEqual({
      ok: true,
      data: {
        organizationId: ORG,
        cycleId: CICLO,
        cicloStatus: "ATIVO",
        escopo: "ESCOPO_APLICADO",
        metas: [
          {
            id: META,
            organizationId: ORG,
            cycleId: CICLO,
            collaboratorId: COLABORADOR,
            tipo: "NEGOCIO_PROJETO",
            descricao: "Reduzir retrabalho",
            kpi: "Retrabalho por lote",
            valorAlvo: "<= 2%",
            status: "EM_ANDAMENTO",
            progressoPercentual: 40,
            resultadoAtual: "45",
            resultadoFinal: null,
            atingida: null,
            excluida: false,
            version: 2,
            relacao: "SELF",
            aprovacoesVigentes: [
              {
                papel: "COORDENADOR",
                aprovacaoId: APROVACAO,
                decididoEm: "2035-02-01T10:00:00.000Z",
                motivo: null,
              },
            ],
          },
        ],
      },
    });
  });

  it("conjunto vazio é ausência EXPLÍCITA de meta autorizada (nunca erro)", async () => {
    const { edge } = edgeFalso({ listarPorEscopo: { ok: true, data: envelope([]) } });
    const resultado = await criarRepositorioMetasSoberanas(edge).listarMetasPorEscopo(ORG, CICLO);

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.data.escopo).toBe("SEM_META_AUTORIZADA");
    expect(resultado.data.metas).toEqual([]);
  });

  it("linha fora do contrato é DESCARTADA (nunca inventa identidade/estado)", async () => {
    const { edge } = edgeFalso({
      listarPorEscopo: {
        ok: true,
        data: envelope([
          linhaMeta(),
          linhaMeta({ goal_id: META_B, tipo: "TIPO_INVENTADO" }),
          linhaMeta({ goal_id: META_B, cycle_id: OUTRO_CICLO }),
          linhaMeta({ goal_id: META_B, version: 1.5 }),
          linhaMeta({ goal_id: META_B, aprovacoes_vigentes: [{ papel: "CHEFE" }] }),
          "linha-invalida",
        ]),
      },
    });
    const resultado = await criarRepositorioMetasSoberanas(edge).listarMetasPorEscopo(ORG, CICLO);

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.data.metas.map((meta) => meta.id)).toEqual([META]);
  });

  it("envelope anômalo (tenant/ciclo divergente ou sem `metas`) é INTERNAL", async () => {
    const outoTenant = edgeFalso({
      listarPorEscopo: { ok: true, data: envelope([], { organization_id: OUTRA_ORG }) },
    });
    expect(
      await criarRepositorioMetasSoberanas(outoTenant.edge).listarMetasPorEscopo(ORG, CICLO)
    ).toEqual({
      ok: false,
      error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
    });

    const semMetas = edgeFalso({ listarPorEscopo: { ok: true, data: { organization_id: ORG } } });
    expect(
      await criarRepositorioMetasSoberanas(semMetas.edge).listarMetasPorEscopo(ORG, CICLO)
    ).toEqual({
      ok: false,
      error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
    });
  });

  it("erros do adapter propagam como Resultado* fail-closed (leitura e mutação)", async () => {
    const negado = edgeFalso({
      listarPorEscopo: {
        ok: false,
        error: { code: "FORBIDDEN", message: "Você não tem permissão." },
      },
    });
    expect(
      await criarRepositorioMetasSoberanas(negado.edge).listarMetasPorEscopo(ORG, CICLO)
    ).toEqual({ ok: false, error: { code: "FORBIDDEN", message: "Você não tem permissão." } });

    const conflito = edgeFalso({
      editar: { ok: false, error: { code: "CONFLICT", message: "Versão divergente." } },
    });
    expect(
      await criarRepositorioMetasSoberanas(conflito.edge).editarMeta({
        ...ENTRADA_BASE,
        descricao: "d",
        kpi: "k",
        valorAlvo: "v",
      })
    ).toEqual({ ok: false, error: { code: "CONFLICT", message: "Versão divergente." } });
  });

  it("payload de mutação fora do contrato vira INTERNAL (nunca sucesso presumido)", async () => {
    const { edge } = edgeFalso({
      editar: { ok: true, data: null },
      criar: { ok: true, data: {} },
    });
    const repositorio = criarRepositorioMetasSoberanas(edge);

    expect(
      await repositorio.editarMeta({ ...ENTRADA_BASE, descricao: "d", kpi: "k", valorAlvo: "v" })
    ).toEqual({
      ok: false,
      error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
    });
    expect(
      await repositorio.criarMeta({
        organizationId: ORG,
        cycleId: CICLO,
        collaboratorId: COLABORADOR,
        tipo: "INDIVIDUAL",
        descricao: "d",
        kpi: "k",
        valorAlvo: "v",
      })
    ).toEqual({
      ok: false,
      error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
    });
  });

  it("organização ausente e UUID malformado recusam SEM atravessar a fronteira", async () => {
    const { edge, invocacoes } = edgeFalso();
    const repositorio = criarRepositorioMetasSoberanas(edge);

    expect(await repositorio.listarMetasPorEscopo("", CICLO)).toEqual({
      ok: false,
      error: { code: "FORBIDDEN", message: "Organização ativa ausente." },
    });
    expect(await repositorio.listarMetasPorEscopo(ORG, "2035-1")).toEqual({
      ok: false,
      error: { code: "INVALID_INPUT", message: "Identificador de ciclo inválido." },
    });
    // Identidade NUNCA vem de rótulo (`ano`/`numero` ou nome).
    expect(
      await repositorio.editarMeta({
        ...ENTRADA_BASE,
        goalId: "meta-1",
        descricao: "d",
        kpi: "k",
        valorAlvo: "v",
      })
    ).toEqual({
      ok: false,
      error: { code: "INVALID_INPUT", message: "Identificador de meta inválido." },
    });
    expect(
      await repositorio.definirLimitesDoCiclo({
        organizationId: ORG,
        cycleId: "ciclo-1",
        tipo: "INDIVIDUAL",
        quantidade: 1,
        motivo: "m",
        expectedVersion: 1,
      })
    ).toEqual({
      ok: false,
      error: { code: "INVALID_INPUT", message: "Identificador de ciclo inválido." },
    });

    expect(invocacoes).toEqual([]);
  });

  it("`operationId` do chamador é preservado; ausente é gerado (idempotência D11)", async () => {
    const { edge, invocacoes } = edgeFalso({ listarPorEscopo: { ok: true, data: envelope([]) } });
    const repositorio = criarRepositorioMetasSoberanas(edge);

    await repositorio.listarMetasPorEscopo(ORG, CICLO, { operationId: OPERACAO });
    await repositorio.listarMetasPorEscopo(ORG, CICLO);

    expect(invocacoes[0]!.entrada.operationId).toBe(OPERACAO);
    expect(invocacoes[1]!.entrada.operationId).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    );
  });
});

describe("F5-10 P5 — repositório soberano de metas (D22-A: sem tabela, sem RLS)", () => {
  it("NENHUMA tabela é acessada: sem `from`, sem rpc, sem cliente Supabase", () => {
    const codigo = apenasCodigo(repositorioFonte as string);
    expect(codigo).not.toMatch(/\.from\s*\(/);
    expect(codigo).not.toMatch(/\.rpc\s*\(/);
    expect(codigo).not.toContain("evaluation_goals");
    expect(codigo).not.toContain("supabaseClient");
    expect(codigo).not.toContain("criarClienteSupabase");
    expect(codigo).not.toContain("localStorage");
    expect(codigo).not.toContain("service_role");
    expect(codigo).not.toContain("SERVICE_ROLE");
    // A dependência é EXCLUSIVAMENTE o adapter da Edge.
    expect(codigo).toContain("edge.listarPorEscopo(");
  });
});
