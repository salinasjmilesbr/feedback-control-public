import { describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import adapterFonte from "./edgeObservacoes.ts?raw";
import {
  DEFINICAO_POR_OPERACAO,
  OPERACOES_OBSERVACAO,
  RPC_POR_OPERACAO,
  capacidadeAdministrativaDaOperacao,
  ehOperacaoFuncional,
  ehOperacaoObservacao,
} from "./contrato";
import {
  FUNCAO_OBSERVACOES,
  criarEdgeObservacoes,
  type RespostaEdgeObservacoes,
} from "./edgeObservacoes";

/**
 * F5-11 P4 (Issue #248) — adapter de cliente da Edge `observacoes`.
 *
 * Espelha `src/infrastructure/supabase/metas/edgeMetas.test.ts` (F5-10 P5).
 * Prova que o cliente envia apenas INTENÇÃO (alvo UUID, versão esperada, campos
 * de domínio da observação, motivo, `operation_id`), que nenhuma autoridade
 * textual viaja no corpo e que a resposta é FAIL-CLOSED nos TRÊS caminhos de
 * erro: `error` de transporte, `error` no corpo 2xx e `data.ok !== true` (2xx
 * fora do contrato). Código desconhecido NUNCA vira sucesso: vira `FORBIDDEN`.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const OBSERVACAO = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const CICLO = "55555555-5555-4555-8555-555555555555";
const COLABORADOR = "77777777-7777-4777-8777-777777777777";
const OPERACAO = "66666666-6666-4666-8666-666666666666";
const UNIDADE = "33333333-3333-4333-8333-333333333333";

/** Os 8 códigos públicos da fronteira (F0-05) — a lista é fechada. */
const CODIGOS_PUBLICOS = [
  "FORBIDDEN",
  "NOT_FOUND",
  "CONFLICT",
  "INVALID_INPUT",
  "INTERNAL",
  "NOT_AUTHORIZED",
  "METHOD_NOT_ALLOWED",
] as const;

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
  data?: RespostaEdgeObservacoes | null;
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
      throw new Error("o adapter de observacoes NAO pode ler tabela");
    },
    rpc: () => {
      proibidas.push("rpc");
      throw new Error("o browser NAO pode chamar RPC do banco");
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
  observationId: OBSERVACAO,
  expectedVersion: 3,
  operationId: OPERACAO,
} as const;

describe("F5-11 P4 — adapter da Edge `observacoes` (forma da intenção)", () => {
  it("criar envia operação, alvo e intenção (sem alvo sintético nem autoridade)", async () => {
    const { cliente, invocacoes } = clienteFalso({
      data: {
        ok: true,
        resultado: {
          observation_id: OBSERVACAO,
          author_user_profile_id: OPERACAO,
          version: 0,
          comunicado: false,
        },
      },
    });
    const resultado = await criarEdgeObservacoes(cliente).criar({
      organizationId: ORG,
      cycleId: CICLO,
      collaboratorId: COLABORADOR,
      tipo: "POSITIVA",
      texto: "Entrega dentro do prazo combinado.",
      operationId: OPERACAO,
    });

    expect(resultado).toEqual({
      ok: true,
      data: {
        observation_id: OBSERVACAO,
        author_user_profile_id: OPERACAO,
        version: 0,
        comunicado: false,
      },
    });
    expect(invocacoes[0]!.funcao).toBe(FUNCAO_OBSERVACOES);
    expect(invocacoes[0]!.corpo).toEqual({
      organization_id: ORG,
      operacao: "observacao.criar",
      operation_id: OPERACAO,
      cycle_id: CICLO,
      collaborator_id: COLABORADOR,
      tipo: "POSITIVA",
      texto: "Entrega dentro do prazo combinado.",
    });
    // A criação NÃO envia versão: a observação ainda não existe (o banco
    // atribui `version = 0`) e o autor é derivado de `auth.uid()` server-side.
    expect(invocacoes[0]!.corpo.expected_version).toBeUndefined();
    expect(invocacoes[0]!.corpo.comunicado).toBeUndefined();
  });

  it("cada operação envia exatamente o seu contrato (sem campos de autoridade)", async () => {
    const { cliente, invocacoes } = clienteFalso({
      data: {
        ok: true,
        resultado: { observation_id: OBSERVACAO, version: 4, comunicado: true },
      },
    });
    const edge = criarEdgeObservacoes(cliente);

    await edge.editar({
      ...ENTRADA_BASE,
      tipo: "NEUTRA",
      texto: "Texto revisado.",
      comunicado: true,
    });
    await edge.definirComunicado({ ...ENTRADA_BASE, comunicado: true });
    await edge.excluir({ ...ENTRADA_BASE, motivo: "Registro duplicado." });
    await edge.revogar({ ...ENTRADA_BASE, motivo: "Exclusao indevida." });
    await edge.obter({ organizationId: ORG, observationId: OBSERVACAO, operationId: OPERACAO });
    await edge.listarPorEscopo({
      organizationId: ORG,
      escopo: "DIRECT_REPORTS",
      organizationalUnitId: UNIDADE,
      operationId: OPERACAO,
    });
    await edge.historico({ organizationId: ORG, observationId: OBSERVACAO, operationId: OPERACAO });

    expect(invocacoes.map((item) => item.corpo.operacao)).toEqual([
      "observacao.editar",
      "observacao.definir_comunicado",
      "observacao.excluir",
      "observacao.revogar",
      "observacao.obter",
      "observacao.listar_por_escopo",
      "observacao.historico",
    ]);

    // Nenhum campo de autoria/tenant/estado/autorização viaja no corpo: a
    // identidade é `auth.uid()`, o estado vem da LINHA soberana e a decisão, do
    // Policy Engine + do gate da RPC.
    const proibidos = [
      "actor_id",
      "actorId",
      "actor_user_profile_id",
      "author_id",
      "authorId",
      "author_user_profile_id",
      "author_collaborator_id",
      "author_membership_id",
      "membership_id",
      "status",
      "aprovado",
      "domainState",
      "excluida",
      "excluida_em",
      "version",
      "capability",
      "scope",
      "role",
      "cargo",
      "funcao",
      "payload_hash",
    ];
    for (const invocacao of invocacoes) {
      for (const proibido of proibidos) {
        expect(Object.keys(invocacao.corpo), proibido).not.toContain(proibido);
      }
      expect(invocacao.corpo.organization_id).toBe(ORG);
      expect(invocacao.corpo.operation_id).toBe(OPERACAO);
    }

    // Alvo por operação: observação EXISTENTE versus escopo de leitura.
    for (const invocacao of invocacoes) {
      const operacao = invocacao.corpo.operacao;
      if (operacao === "observacao.listar_por_escopo") {
        expect(invocacao.corpo.observation_id).toBeUndefined();
        expect(invocacao.corpo.escopo).toBe("DIRECT_REPORTS");
        expect(invocacao.corpo.organizational_unit_id).toBe(UNIDADE);
        // D21: o INSTANTE da decisão é soberano — a listagem NÃO transporta data
        // declarada pelo chamador (a chave nem existe no corpo).
        expect(
          Object.prototype.hasOwnProperty.call(invocacao.corpo, "data"),
          "listar_por_escopo:data"
        ).toBe(false);
        expect(invocacao.corpo.data).toBeUndefined();
      } else if (operacao === "observacao.criar") {
        expect(invocacao.corpo.observation_id).toBeUndefined();
      } else {
        expect(invocacao.corpo.observation_id).toBe(OBSERVACAO);
        expect(invocacao.corpo.escopo).toBeUndefined();
      }
    }

    // Toda mutação de linha EXISTENTE envia a versão esperada (concorrência
    // otimista); leituras não enviam versão.
    for (const invocacao of invocacoes) {
      const operacao = String(invocacao.corpo.operacao);
      const mutacao = !operacao.endsWith(".obter") && !operacao.endsWith(".historico");
      if (operacao === "observacao.listar_por_escopo") continue;
      if (mutacao) {
        expect(typeof invocacao.corpo.expected_version, operacao).toBe("number");
      } else {
        expect(invocacao.corpo.expected_version, operacao).toBeUndefined();
      }
    }

    // `motivo` é obrigatório na exclusão/revogação (a RPC o exige não vazio).
    for (const operacao of ["observacao.excluir", "observacao.revogar"] as const) {
      const invocacao = invocacoes.find((item) => item.corpo.operacao === operacao);
      expect(invocacao === undefined, operacao).toBe(false);
      expect(typeof invocacao?.corpo.motivo, operacao).toBe("string");
    }

    // D21: NENHUMA operação transporta data/instante declarado pelo chamador — o
    // instante da decisão é SOBERANO (a Edge/RPC preenche `p_data` server-side).
    for (const invocacao of invocacoes) {
      for (const chave of ["data", "data_referencia", "instante", "p_data"]) {
        expect(
          Object.prototype.hasOwnProperty.call(invocacao.corpo, chave),
          `${String(invocacao.corpo.operacao)}:${chave}`
        ).toBe(false);
      }
    }
  });

  it("as leituras (`obter`/`historico`) NÃO inventam `expected_version`, `comunicado` nem `data`", async () => {
    const { cliente, invocacoes } = clienteFalso({
      data: { ok: true, resultado: { observation_id: OBSERVACAO } },
    });
    const edge = criarEdgeObservacoes(cliente);

    await edge.obter({ organizationId: ORG, observationId: OBSERVACAO, operationId: OPERACAO });
    await edge.historico({
      organizationId: ORG,
      observationId: OBSERVACAO,
      operationId: OPERACAO,
    });

    for (const invocacao of invocacoes) {
      expect(Object.keys(invocacao.corpo)).not.toContain("expected_version");
      expect(Object.keys(invocacao.corpo)).not.toContain("comunicado");
      expect(Object.keys(invocacao.corpo)).not.toContain("motivo");
      expect(Object.keys(invocacao.corpo)).not.toContain("texto");
      // D21: o instante da decisão nunca viaja como intenção de leitura.
      expect(Object.keys(invocacao.corpo)).not.toContain("data");
    }
  });

  it("o adapter oferece exatamente as OITO operações contratadas", () => {
    const codigo = apenasCodigo(adapterFonte as string);
    for (const operacao of [
      "observacao.criar",
      "observacao.editar",
      "observacao.definir_comunicado",
      "observacao.excluir",
      "observacao.revogar",
      "observacao.obter",
      "observacao.listar_por_escopo",
      "observacao.historico",
    ]) {
      expect(codigo.split(`"${operacao}"`).length - 1, operacao).toBe(1);
    }
    // O adapter não inventa operação fora do contrato congelado. A checagem é por
    // CONJUNTO de literais `observacao.<...>` do fonte: comparação por SUBSTRING
    // seria um falso positivo, porque `observacao.listar` é prefixo legítimo de
    // `observacao.listar_por_escopo` (contrato congelado).
    const literaisDeOperacao = codigo.match(/observacao\.[a-z_]+/g) ?? [];
    expect(new Set(literaisDeOperacao)).toEqual(new Set(OPERACOES_OBSERVACAO));
    expect(codigo).not.toContain("observacao.revogar_exclusao");
    expect(codigo).toContain('FUNCAO_OBSERVACOES = "observacoes"');
  });
});

describe("F5-11 P4 — adapter da Edge `observacoes` (fail-closed)", () => {
  it("sucesso devolve o `resultado` CRU da RPC (a fronteira não inventa campos)", async () => {
    const bruto = {
      observation_id: OBSERVACAO,
      escopo: "SELF",
      total: 1,
      itens: [{ observation_id: OBSERVACAO }],
      extra: 1,
    };
    const { cliente } = clienteFalso({ data: { ok: true, resultado: bruto } });
    const resultado = await criarEdgeObservacoes(cliente).listarPorEscopo({
      organizationId: ORG,
      escopo: "SELF",
      operationId: OPERACAO,
    });

    expect(resultado).toEqual({ ok: true, data: bruto });
  });

  it("`resultado: null` é SUCESSO explícito (a chave existe no contrato)", async () => {
    const { cliente } = clienteFalso({ data: { ok: true, resultado: null } });
    const resultado = await criarEdgeObservacoes(cliente).excluir({
      ...ENTRADA_BASE,
      motivo: "x",
    });

    expect(resultado).toEqual({ ok: true, data: null });
  });

  it("caminho 3 — 2xx SEM `ok: true` NÃO é sucesso presumido", async () => {
    for (const data of [
      { resultado: { observation_id: OBSERVACAO } },
      { ok: "true", resultado: { observation_id: OBSERVACAO } },
      { ok: false, resultado: { observation_id: OBSERVACAO } },
      { operacao: "observacao.obter" },
      null,
    ] as const) {
      const { cliente } = clienteFalso({ data });
      expect(
        await criarEdgeObservacoes(cliente).obter({
          organizationId: ORG,
          observationId: OBSERVACAO,
          operationId: OPERACAO,
        }),
        JSON.stringify(data)
      ).toEqual({
        ok: false,
        error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
      });
    }
  });

  it("caminho 3 — 2xx com `ok: true` mas SEM a chave `resultado` também é recusado", async () => {
    const { cliente } = clienteFalso({ data: { ok: true, operacao: "observacao.revogar" } });
    expect(
      await criarEdgeObservacoes(cliente).revogar({ ...ENTRADA_BASE, motivo: "x" })
    ).toEqual({
      ok: false,
      error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
    });
  });

  it("caminho 2 — `error` no corpo 2xx preserva código público e mensagem da Edge", async () => {
    const { cliente } = clienteFalso({
      data: { error: { code: "CONFLICT", message: "Versão divergente." } },
    });
    const resultado = await criarEdgeObservacoes(cliente).editar({
      ...ENTRADA_BASE,
      tipo: "NEUTRA",
      texto: "d",
      comunicado: false,
    });

    expect(resultado).toEqual({
      ok: false,
      error: { code: "CONFLICT", message: "Versão divergente." },
    });
  });

  it("caminho 2 — código desconhecido vira FORBIDDEN e mensagem ausente vira texto padrão", async () => {
    const { cliente } = clienteFalso({ data: { error: { code: "CODIGO_NOVO" } } });
    const resultado = await criarEdgeObservacoes(cliente).definirComunicado({
      ...ENTRADA_BASE,
      comunicado: true,
    });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("FORBIDDEN");
    expect(resultado.error.message).toBe("Operação de observação recusada.");
  });

  it("caminho 1 — erro de transporte com corpo em `context` expõe código público", async () => {
    const { cliente } = clienteFalso({
      error: { context: { error: { code: "NOT_AUTHORIZED", message: "Sessão inválida." } } },
    });
    const resultado = await criarEdgeObservacoes(cliente).historico({
      organizationId: ORG,
      observationId: OBSERVACAO,
      operationId: OPERACAO,
    });

    expect(resultado).toEqual({
      ok: false,
      error: { code: "NOT_AUTHORIZED", message: "Sessão inválida." },
    });
  });

  it("caminho 1 — erro de transporte SEM corpo é recusado com mensagem padrão", async () => {
    // `error` VERDADEIRO = falha de TRANSPORTE: o corpo público não é legível
    // (`errosEdge.ts` devolve `null`) ⇒ o adapter aplica código/mensagem PADRÃO,
    // nunca sucesso presumido (molde `edgeMetas.test.ts:339-347`).
    for (const error of [{}, "falha", { context: null }, { context: {} }]) {
      const { cliente } = clienteFalso({ error });
      const resultado = await criarEdgeObservacoes(cliente).excluir({
        ...ENTRADA_BASE,
        motivo: "x",
      });

      expect(resultado.ok, JSON.stringify(error)).toBe(false);
      if (resultado.ok) return;
      expect(resultado.error.code).toBe("FORBIDDEN");
      expect(resultado.error.message).toBe("Operação de observação recusada.");
    }
  });

  it("caminho 3 — `error` AUSENTE com resposta fora do contrato vira INTERNAL", async () => {
    // Sem falha de transporte (`error` falsy) NÃO é caminho 1: é resposta
    // INESPERADA do servidor (caminho 3, §17.1 P4) — devolver `FORBIDDEN` aqui
    // daria diagnóstico falso a um defeito de contrato da própria Edge.
    for (const error of [null, undefined]) {
      const { cliente } = clienteFalso({ error });
      const resultado = await criarEdgeObservacoes(cliente).excluir({
        ...ENTRADA_BASE,
        motivo: "x",
      });

      expect(resultado.ok, JSON.stringify(error)).toBe(false);
      if (resultado.ok) return;
      expect(resultado.error.code).toBe("INTERNAL");
      expect(resultado.error.message).toBe("Resposta inesperada do servidor.");
    }
  });

  it("caminho 1 — código fora da lista fechada em `context` também vira FORBIDDEN", async () => {
    const { cliente } = clienteFalso({
      error: { context: { error: { code: "TEAPOT", message: "?" } } },
    });
    const resultado = await criarEdgeObservacoes(cliente).revogar({
      ...ENTRADA_BASE,
      motivo: "x",
    });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("FORBIDDEN");
  });

  it("TODOS os códigos públicos atravessam os dois caminhos de resposta de erro", async () => {
    for (const codigo of CODIGOS_PUBLICOS) {
      const noCorpo = clienteFalso({
        data: { error: { code: codigo, message: `recusa ${codigo}` } },
      });
      expect(
        await criarEdgeObservacoes(noCorpo.cliente).obter({
          organizationId: ORG,
          observationId: OBSERVACAO,
          operationId: OPERACAO,
        }),
        codigo
      ).toEqual({ ok: false, error: { code: codigo, message: `recusa ${codigo}` } });

      const noTransporte = clienteFalso({
        error: { context: { error: { code: codigo, message: `recusa ${codigo}` } } },
      });
      expect(
        await criarEdgeObservacoes(noTransporte.cliente).obter({
          organizationId: ORG,
          observationId: OBSERVACAO,
          operationId: OPERACAO,
        }),
        codigo
      ).toEqual({ ok: false, error: { code: codigo, message: `recusa ${codigo}` } });
    }
    // A lista é FECHADA: nenhum código fora dela é aceito (e a mensagem da Edge
    // nunca é substituída por texto cru do banco).
    for (const desconhecido of ["F5_11_FORBIDDEN", "FORBIDDEN ", "", 42, null, undefined]) {
      const { cliente } = clienteFalso({
        data: { error: { code: desconhecido, message: "msg" } },
      });
      const resultado = await criarEdgeObservacoes(cliente).obter({
        organizationId: ORG,
        observationId: OBSERVACAO,
        operationId: OPERACAO,
      });
      expect(resultado.ok, String(desconhecido)).toBe(false);
      if (resultado.ok) return;
      expect(resultado.error.code, String(desconhecido)).toBe("FORBIDDEN");
    }
  });
});

describe("F5-11 P4 — adapter da Edge `observacoes` (sem fallback)", () => {
  it("NÃO chama rpc/from e NÃO usa armazenamento local", async () => {
    const { cliente, proibidas } = clienteFalso({ data: { ok: true, resultado: {} } });
    await criarEdgeObservacoes(cliente).listarPorEscopo({
      organizationId: ORG,
      escopo: "SELF",
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
    expect(codigo).not.toContain("observacaoStorage");
    expect(codigo).not.toContain("feedback-control-observacoes");
  });
});

describe("F5-11 P4 — contrato `observacoes` (gate, capability e mapa de RPC)", () => {
  it("o mapa é EXAUSTIVO (8 operações, sem fallback) e coerente com `gate`/`funcional`", () => {
    expect(OPERACOES_OBSERVACAO).toHaveLength(8);
    expect(OPERACOES_OBSERVACAO).toEqual([
      "observacao.criar",
      "observacao.editar",
      "observacao.definir_comunicado",
      "observacao.excluir",
      "observacao.revogar",
      "observacao.obter",
      "observacao.listar_por_escopo",
      "observacao.historico",
    ]);
    expect(ehOperacaoObservacao("observacao.revogar_exclusao")).toBe(false);
    expect(ehOperacaoObservacao("observation.criar")).toBe(false);
    expect(ehOperacaoObservacao("observacao.obter")).toBe(true);

    for (const operacao of OPERACOES_OBSERVACAO) {
      const definicao = DEFINICAO_POR_OPERACAO[operacao];
      // `funcional` é DERIVADO de `gate` (ponte de compatibilidade com a Edge).
      expect(definicao.funcional, operacao).toBe(definicao.gate === "funcional");
      expect(ehOperacaoFuncional(operacao), operacao).toBe(definicao.funcional);
    }

    // §8 linha 1 (norma): `observacao.listar_por_escopo` é ADMINISTRATIVA — não
    // existe alvo de observação numa listagem (molde `goal.listar_por_escopo`:
    // capability efetiva do ator na organização, sem alvo no Policy Engine).
    const listagem = DEFINICAO_POR_OPERACAO["observacao.listar_por_escopo"];
    expect(listagem.gate).toBe("administrativo");
    expect(listagem.funcional).toBe(false);
    expect(ehOperacaoFuncional("observacao.listar_por_escopo")).toBe(false);
    expect(capacidadeAdministrativaDaOperacao("observacao.listar_por_escopo")).toBe(
      "observation.read"
    );

    // As outras SETE são FUNCIONAIS com recurso real e NUNCA devolvem capability
    // administrativa (sem caminho alternativo de decisão).
    for (const operacao of OPERACOES_OBSERVACAO) {
      if (operacao === "observacao.listar_por_escopo") continue;
      expect(DEFINICAO_POR_OPERACAO[operacao].gate, operacao).toBe("funcional");
      expect(ehOperacaoFuncional(operacao), operacao).toBe(true);
      expect(capacidadeAdministrativaDaOperacao(operacao), operacao).toBeNull();
    }
  });

  it("cada operação aponta para UMA RPC soberana existente (mapa congelado)", () => {
    expect(Object.keys(RPC_POR_OPERACAO)).toHaveLength(8);
    expect(RPC_POR_OPERACAO["observacao.criar"]).toBe("observacao_criar");
    expect(RPC_POR_OPERACAO["observacao.editar"]).toBe("observacao_editar");
    expect(RPC_POR_OPERACAO["observacao.definir_comunicado"]).toBe(
      "observacao_definir_comunicado"
    );
    expect(RPC_POR_OPERACAO["observacao.excluir"]).toBe("observacao_excluir");
    expect(RPC_POR_OPERACAO["observacao.revogar"]).toBe("observacao_revogar");
    expect(RPC_POR_OPERACAO["observacao.obter"]).toBe("observacao_obter");
    expect(RPC_POR_OPERACAO["observacao.listar_por_escopo"]).toBe(
      "observacao_listar_por_escopo"
    );
    expect(RPC_POR_OPERACAO["observacao.historico"]).toBe("observacao_historico");
    // Nenhuma função INTERNA (`f5_11_*`) entra como operação de cliente.
    for (const rpc of Object.values(RPC_POR_OPERACAO)) {
      expect(rpc.startsWith("observacao_"), rpc).toBe(true);
      expect(rpc).not.toContain("f5_11_");
      expect(rpc).not.toContain("invalidar");
    }
  });
});
