import { describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import adapterFonte from "./edgeMetas.ts?raw";
import {
  DEFINICAO_POR_OPERACAO,
  OPERACOES_META,
  RPC_POR_OPERACAO,
  capacidadeAdministrativaDaOperacao,
  ehOperacaoFuncional,
  ehOperacaoMeta,
} from "./contrato";
import {
  FUNCAO_METAS,
  criarEdgeMetas,
  type RespostaEdgeMetas,
} from "./edgeMetas";

/**
 * F5-10 P5 (Issue #218), Bloco 1/S2 — adapter de cliente da Edge `metas`.
 *
 * Prova que o cliente envia apenas INTENÇÃO (alvo UUID, versão esperada, campos
 * de domínio, motivo, `operation_id`), que nenhuma autoridade textual viaja no
 * corpo e que a resposta é FAIL-CLOSED: erro de transporte, `error` no corpo,
 * 2xx fora do contrato e código desconhecido NUNCA viram sucesso presumido.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const META = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CICLO = "55555555-5555-4555-8555-555555555555";
const COLABORADOR = "77777777-7777-4777-8777-777777777777";
const OPERACAO = "66666666-6666-4666-8666-666666666666";

interface Invocacao {
  readonly funcao: string;
  readonly corpo: Record<string, unknown>;
}

interface ClienteFalso {
  readonly cliente: SupabaseClient;
  readonly invocacoes: Invocacao[];
  /** Chamadas proibidas interceptadas (`rpc`/`from`) — o adapter não pode fazer nenhuma. */
  readonly proibidas: string[];
}

function clienteFalso(resposta: {
  data?: RespostaEdgeMetas | null;
  error?: unknown;
}): ClienteFalso {
  const invocacoes: Invocacao[] = [];
  const proibidas: string[] = [];
  const cliente = {
    functions: {
      invoke: async (funcao: string, opcoes: { body: Record<string, unknown> }) => {
        invocacoes.push({ funcao, corpo: opcoes.body });
        return { data: resposta.data ?? null, error: resposta.error ?? null };
      },
    },
    from: () => {
      proibidas.push("from");
      throw new Error("o adapter de metas NÃO pode ler tabela (D22-A)");
    },
    rpc: () => {
      proibidas.push("rpc");
      throw new Error("o browser NÃO pode chamar RPC do banco");
    },
  } as unknown as SupabaseClient;
  return { cliente, invocacoes, proibidas };
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

const ENTRADA_BASE = {
  organizationId: ORG,
  goalId: META,
  expectedVersion: 3,
  operationId: OPERACAO,
} as const;

describe("F5-10 P5 — adapter da Edge `metas` (forma da intenção)", () => {
  it("criar envia operação, alvo e intenção (sem alvo sintético nem autoridade)", async () => {
    const { cliente, invocacoes } = clienteFalso({
      data: { ok: true, resultado: { goal_id: META, version: 0, status: "EM_ANDAMENTO" } },
    });
    const resultado = await criarEdgeMetas(cliente).criar({
      organizationId: ORG,
      cycleId: CICLO,
      collaboratorId: COLABORADOR,
      tipo: "NEGOCIO_PROJETO",
      descricao: "Reduzir retrabalho",
      kpi: "Retrabalho por lote",
      valorAlvo: "<= 2%",
      operationId: OPERACAO,
    });

    expect(resultado).toEqual({
      ok: true,
      data: { goal_id: META, version: 0, status: "EM_ANDAMENTO" },
    });
    expect(invocacoes[0]!.funcao).toBe(FUNCAO_METAS);
    expect(invocacoes[0]!.corpo).toEqual({
      organization_id: ORG,
      operacao: "goal.criar",
      operation_id: OPERACAO,
      cycle_id: CICLO,
      collaborator_id: COLABORADOR,
      tipo: "NEGOCIO_PROJETO",
      descricao: "Reduzir retrabalho",
      kpi: "Retrabalho por lote",
      valor_alvo: "<= 2%",
    });
  });

  it("cada operação envia exatamente o seu contrato (sem campos de autoridade)", async () => {
    const { cliente, invocacoes } = clienteFalso({
      data: { ok: true, resultado: { goal_id: META, version: 4, status: "EM_ANDAMENTO" } },
    });
    const edge = criarEdgeMetas(cliente);

    await edge.editar({
      ...ENTRADA_BASE,
      descricao: "Nova descricao",
      kpi: "Novo KPI",
      valorAlvo: "100",
    });
    await edge.atualizarProgresso({
      ...ENTRADA_BASE,
      resultadoAtual: "50",
      progressoPercentual: 50,
    });
    await edge.finalizar({ ...ENTRADA_BASE, resultadoFinal: "100", atingida: true });
    await edge.revisarFinalizacao({
      ...ENTRADA_BASE,
      resultadoFinal: "80",
      atingida: false,
      motivo: "Correcao do fechamento",
    });
    await edge.excluir({ ...ENTRADA_BASE, motivo: "Duplicada" });
    await edge.aprovar({ ...ENTRADA_BASE, papel: "COORDENADOR", motivo: "Conferido" });
    await edge.definirLimitesDoCiclo({
      organizationId: ORG,
      cycleId: CICLO,
      tipo: "INDIVIDUAL",
      quantidade: 3,
      motivo: "Ampliacao do ciclo",
      expectedVersion: 7,
      operationId: OPERACAO,
    });
    await edge.listarPorEscopo({ organizationId: ORG, cycleId: CICLO, operationId: OPERACAO });

    expect(invocacoes.map((item) => item.corpo.operacao)).toEqual([
      "goal.editar",
      "goal.atualizar_progresso",
      "goal.finalizar",
      "goal.revisar_finalizacao",
      "goal.excluir",
      "goal.aprovar",
      "goal.definir_limites_do_ciclo",
      "goal.listar_por_escopo",
    ]);

    const proibidos = [
      "actor_id",
      "actorId",
      "actor_user_profile_id",
      "author_id",
      "authorId",
      "membership_id",
      "status",
      "aprovado",
      "domainState",
      "excluida",
      "version",
      "capability",
      "role",
      "cargo",
      "funcao",
      "p_payload_hash",
      "payload_hash",
    ];
    for (const invocacao of invocacoes) {
      for (const proibido of proibidos) {
        expect(Object.keys(invocacao.corpo), proibido).not.toContain(proibido);
      }
      expect(invocacao.corpo.organization_id).toBe(ORG);
      expect(invocacao.corpo.operation_id).toBe(OPERACAO);
    }

    // Alvo por operação: meta existente versus ciclo.
    for (const invocacao of invocacoes) {
      const operacao = invocacao.corpo.operacao;
      if (operacao === "goal.listar_por_escopo" || operacao === "goal.definir_limites_do_ciclo") {
        expect(invocacao.corpo.goal_id).toBeUndefined();
        expect(invocacao.corpo.cycle_id).toBe(CICLO);
      } else {
        expect(invocacao.corpo.goal_id).toBe(META);
        expect(invocacao.corpo.cycle_id).toBeUndefined();
      }
    }

    // D12: toda mutação de meta/limite EXISTENTE envia a versão esperada.
    for (const invocacao of invocacoes) {
      if (invocacao.corpo.operacao === "goal.listar_por_escopo") continue;
      expect(typeof invocacao.corpo.expected_version, String(invocacao.corpo.operacao)).toBe(
        "number"
      );
    }
  });

  it("motivo opcional não é inventado quando ausente", async () => {
    const { cliente, invocacoes } = clienteFalso({
      data: { ok: true, resultado: { goal_id: META, version: 5, status: "ATINGIDA" } },
    });
    const edge = criarEdgeMetas(cliente);

    await edge.revisarFinalizacao({ ...ENTRADA_BASE, resultadoFinal: "100", atingida: true });
    await edge.aprovar({ ...ENTRADA_BASE, papel: "GERENTE" });

    expect(Object.keys(invocacoes[0]!.corpo)).not.toContain("motivo");
    expect(Object.keys(invocacoes[1]!.corpo)).not.toContain("motivo");
  });

  it("o adapter oferece exatamente as NOVE operações contratadas", () => {
    const codigo = apenasCodigo(adapterFonte as string);
    for (const operacao of [
      "goal.criar",
      "goal.editar",
      "goal.atualizar_progresso",
      "goal.finalizar",
      "goal.revisar_finalizacao",
      "goal.excluir",
      "goal.aprovar",
      "goal.definir_limites_do_ciclo",
      "goal.listar_por_escopo",
    ]) {
      expect(codigo.split(`"${operacao}"`).length - 1, operacao).toBe(1);
    }
    // `meta_invalidar_aprovacoes` é INTERNA às mutações (§13) — sem superfície.
    expect(codigo).not.toContain("goal.invalidar_aprovacoes");
    expect(codigo).toContain('FUNCAO_METAS = "metas"');
  });
});

describe("F5-10 P5 — adapter da Edge `metas` (fail-closed)", () => {
  it("sucesso devolve o `resultado` CRU da RPC (a fronteira não inventa campos)", async () => {
    const bruto = { goal_id: META, aprovacao_id: OPERACAO, papel: "GERENTE", extra: 1 };
    const { cliente } = clienteFalso({ data: { ok: true, resultado: bruto } });
    const resultado = await criarEdgeMetas(cliente).aprovar({ ...ENTRADA_BASE, papel: "GERENTE" });

    expect(resultado).toEqual({ ok: true, data: bruto });
  });

  it("`resultado: null` é SUCESSO explícito (a chave existe no contrato)", async () => {
    const { cliente } = clienteFalso({ data: { ok: true, resultado: null } });
    const resultado = await criarEdgeMetas(cliente).excluir({ ...ENTRADA_BASE, motivo: "x" });

    expect(resultado).toEqual({ ok: true, data: null });
  });

  it("2xx fora do contrato NÃO é sucesso presumido", async () => {
    const semOk = clienteFalso({ data: { resultado: { version: 9 } } });
    expect(await criarEdgeMetas(semOk.cliente).finalizar({
      ...ENTRADA_BASE,
      resultadoFinal: "x",
      atingida: true,
    })).toEqual({
      ok: false,
      error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
    });

    const semResultado = clienteFalso({ data: { ok: true, operacao: "goal.finalizar" } });
    expect(await criarEdgeMetas(semResultado.cliente).finalizar({
      ...ENTRADA_BASE,
      resultadoFinal: "x",
      atingida: true,
    })).toEqual({
      ok: false,
      error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
    });
  });

  it("código desconhecido vira FORBIDDEN e mensagem ausente vira texto padrão", async () => {
    const { cliente } = clienteFalso({ data: { error: { code: "CODIGO_NOVO" } } });
    const resultado = await criarEdgeMetas(cliente).editar({
      ...ENTRADA_BASE,
      descricao: "d",
      kpi: "k",
      valorAlvo: "v",
    });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("FORBIDDEN");
    expect(resultado.error.message).toBe("Operação de meta recusada.");
  });

  it("`error` no corpo 2xx preserva código público e mensagem da Edge", async () => {
    const { cliente } = clienteFalso({
      data: { error: { code: "CONFLICT", message: "Versão divergente." } },
    });
    const resultado = await criarEdgeMetas(cliente).editar({
      ...ENTRADA_BASE,
      descricao: "d",
      kpi: "k",
      valorAlvo: "v",
    });

    expect(resultado).toEqual({
      ok: false,
      error: { code: "CONFLICT", message: "Versão divergente." },
    });
  });

  it("erro de transporte com corpo em `context` expõe código público", async () => {
    const { cliente } = clienteFalso({
      error: { context: { error: { code: "NOT_AUTHORIZED", message: "Sessão inválida." } } },
    });
    const resultado = await criarEdgeMetas(cliente).listarPorEscopo({
      organizationId: ORG,
      cycleId: CICLO,
      operationId: OPERACAO,
    });

    expect(resultado).toEqual({
      ok: false,
      error: { code: "NOT_AUTHORIZED", message: "Sessão inválida." },
    });
  });

  it("erro de transporte SEM corpo é recusado com mensagem padrão", async () => {
    const { cliente } = clienteFalso({ error: {} });
    const resultado = await criarEdgeMetas(cliente).excluir({ ...ENTRADA_BASE, motivo: "x" });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("FORBIDDEN");
    expect(resultado.error.message).toBe("Operação de meta recusada.");
  });

  it("código fora da lista fechada em `context` também vira FORBIDDEN", async () => {
    const { cliente } = clienteFalso({
      error: { context: { error: { code: "TEAPOT", message: "?" } } },
    });
    const resultado = await criarEdgeMetas(cliente).aprovar({ ...ENTRADA_BASE, papel: "GERENTE" });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("FORBIDDEN");
  });
});

describe("F5-10 P5 — adapter da Edge `metas` (sem fallback)", () => {
  it("NÃO chama rpc/from e NÃO usa armazenamento local", async () => {
    const { cliente, proibidas } = clienteFalso({ data: { ok: true, resultado: {} } });
    await criarEdgeMetas(cliente).listarPorEscopo({
      organizationId: ORG,
      cycleId: CICLO,
      operationId: OPERACAO,
    });
    expect(proibidas).toEqual([]);

    // Guarda ESTÁTICA no CÓDIGO (comentários removidos): nenhuma via alternativa.
    const codigo = apenasCodigo(adapterFonte as string);
    expect(codigo).not.toMatch(/\.rpc\s*\(/);
    expect(codigo).not.toMatch(/\.from\s*\(/);
    expect(codigo).not.toContain("localStorage");
    expect(codigo).not.toContain("sessionStorage");
    expect(codigo).not.toContain("service_role");
    expect(codigo).not.toContain("SERVICE_ROLE");
  });
});

describe("F5-10 P5 — contrato `metas` (gate, capability e mapa de RPC)", () => {
  it("o mapa é EXAUSTIVO (9 operações, sem fallback) e coerente com `funcional`", () => {
    expect(OPERACOES_META).toHaveLength(9);
    expect(OPERACOES_META).toEqual([
      "goal.criar",
      "goal.editar",
      "goal.atualizar_progresso",
      "goal.finalizar",
      "goal.revisar_finalizacao",
      "goal.excluir",
      "goal.aprovar",
      "goal.definir_limites_do_ciclo",
      "goal.listar_por_escopo",
    ]);
    expect(ehOperacaoMeta("goal.invalidar_aprovacoes")).toBe(false);
    expect(ehOperacaoMeta("goal.listar_por_escopo")).toBe(true);

    for (const operacao of OPERACOES_META) {
      const definicao = DEFINICAO_POR_OPERACAO[operacao];
      // `funcional` é DERIVADO de `gate` (ponte de compatibilidade com a Edge).
      expect(definicao.funcional, operacao).toBe(definicao.gate === "funcional");
      expect(ehOperacaoFuncional(operacao), operacao).toBe(definicao.funcional);
    }

    // D19/D21: só `goal.listar_por_escopo` é ADMINISTRATIVA; as demais NEGAM no
    // plano administrativo (sem capability por default).
    expect(capacidadeAdministrativaDaOperacao("goal.listar_por_escopo")).toBe("goal.read");
    for (const operacao of OPERACOES_META) {
      if (operacao === "goal.listar_por_escopo") continue;
      expect(capacidadeAdministrativaDaOperacao(operacao), operacao).toBeNull();
    }

    // D7/D9: `goal.approve` NÃO implica `goal.write`.
    expect(DEFINICAO_POR_OPERACAO["goal.aprovar"].capability).toBe("goal.approve");
    expect(DEFINICAO_POR_OPERACAO["goal.definir_limites_do_ciclo"].capability).toBe(
      "cycle.manage"
    );
    for (const operacao of [
      "goal.criar",
      "goal.editar",
      "goal.atualizar_progresso",
      "goal.finalizar",
      "goal.revisar_finalizacao",
      "goal.excluir",
    ] as const) {
      expect(DEFINICAO_POR_OPERACAO[operacao].capability, operacao).toBe("goal.write");
    }
  });

  it("cada operação aponta para UMA RPC soberana existente (mapa congelado)", () => {
    expect(Object.keys(RPC_POR_OPERACAO)).toHaveLength(9);
    expect(RPC_POR_OPERACAO["goal.criar"]).toBe("meta_criar");
    expect(RPC_POR_OPERACAO["goal.editar"]).toBe("meta_editar");
    expect(RPC_POR_OPERACAO["goal.atualizar_progresso"]).toBe("meta_atualizar_progresso");
    expect(RPC_POR_OPERACAO["goal.finalizar"]).toBe("meta_finalizar");
    expect(RPC_POR_OPERACAO["goal.revisar_finalizacao"]).toBe("meta_revisar_finalizacao");
    expect(RPC_POR_OPERACAO["goal.excluir"]).toBe("meta_excluir");
    expect(RPC_POR_OPERACAO["goal.aprovar"]).toBe("meta_aprovar");
    expect(RPC_POR_OPERACAO["goal.definir_limites_do_ciclo"]).toBe(
      "meta_definir_limites_do_ciclo"
    );
    expect(RPC_POR_OPERACAO["goal.listar_por_escopo"]).toBe("meta_listar_por_escopo");
    // `meta_invalidar_aprovacoes` é interna às mutações — sem operação de cliente.
    expect(Object.values(RPC_POR_OPERACAO)).not.toContain("meta_invalidar_aprovacoes");
  });
});
