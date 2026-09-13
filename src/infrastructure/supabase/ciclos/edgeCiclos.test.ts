import { describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  FUNCAO_CICLOS,
  criarEdgeCiclos,
  type RespostaEdgeCiclos,
} from "./edgeCiclos";

/**
 * F5-09 P7 (Issue #202) — adapter de cliente da Edge `ciclos`.
 *
 * Prova que o cliente envia apenas INTENÇÃO (alvo UUID, versão, motivo,
 * `operationId`), que nenhuma autoridade textual viaja no corpo e que a
 * resposta é fail-closed: erro de transporte, `error` no corpo, 2xx fora do
 * contrato e código desconhecido NUNCA viram sucesso presumido.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "55555555-5555-4555-8555-555555555555";
const COLABORADOR = "77777777-7777-4777-8777-777777777777";
const OPERACAO = "66666666-6666-4666-8666-666666666666";

interface Invocacao {
  readonly funcao: string;
  readonly corpo: Record<string, unknown>;
}

function clienteFalso(resposta: {
  data?: RespostaEdgeCiclos | null;
  error?: unknown;
}): { readonly cliente: SupabaseClient; readonly invocacoes: Invocacao[] } {
  const invocacoes: Invocacao[] = [];
  const cliente = {
    functions: {
      invoke: async (funcao: string, opcoes: { body: Record<string, unknown> }) => {
        invocacoes.push({ funcao, corpo: opcoes.body });
        return { data: resposta.data ?? null, error: resposta.error ?? null };
      },
    },
  } as unknown as SupabaseClient;
  return { cliente, invocacoes };
}

const ENTRADA_BASE = {
  organizationId: ORG,
  cycleId: CICLO,
  expectedVersion: 2,
  operationId: OPERACAO,
} as const;

describe("F5-09 P7 — adapter da Edge `ciclos` (forma da intenção)", () => {
  it("criar envia operação, ano/numero/datas e o operationId (sem alvo sintético)", async () => {
    const { cliente, invocacoes } = clienteFalso({ data: { ok: true, resultado: { version: 0 } } });
    const resultado = await criarEdgeCiclos(cliente).criar({
      organizationId: ORG,
      ano: 2035,
      numero: 2,
      dataInicio: "2035-04-01",
      dataFim: "2035-06-30",
      operationId: OPERACAO,
    });

    expect(resultado).toEqual({ ok: true, data: { version: 0 } });
    expect(invocacoes[0]!.funcao).toBe(FUNCAO_CICLOS);
    expect(invocacoes[0]!.corpo).toEqual({
      organization_id: ORG,
      operacao: "cycle.criar",
      operation_id: OPERACAO,
      ano: 2035,
      numero: 2,
      data_inicio: "2035-04-01",
      data_fim: "2035-06-30",
    });
  });

  it("cada operação envia exatamente o seu contrato (sem campos de autoridade)", async () => {
    const { cliente, invocacoes } = clienteFalso({ data: { ok: true, resultado: { version: 3 } } });
    const edge = criarEdgeCiclos(cliente);

    await edge.editar({
      ...ENTRADA_BASE,
      ano: 2035,
      numero: 1,
      dataInicio: "2035-01-01",
      dataFim: "2035-03-31",
    });
    await edge.ativar(ENTRADA_BASE);
    await edge.encerrar({ ...ENTRADA_BASE, motivo: "Fim" });
    await edge.cancelar({ ...ENTRADA_BASE, motivo: "Interrupcao" });
    await edge.reabrir({ ...ENTRADA_BASE, motivo: "Erro" });
    await edge.corrigirPeriodo({
      ...ENTRADA_BASE,
      dataInicio: "2035-01-02",
      dataFim: "2035-03-30",
      justificativa: "Ajuste",
    });
    await edge.incluirAdmissao({
      ...ENTRADA_BASE,
      motivo: "Admitido apos a ativacao",
      collaboratorId: COLABORADOR,
    });

    expect(invocacoes.map((item) => item.corpo.operacao)).toEqual([
      "cycle.editar",
      "cycle.ativar",
      "cycle.encerrar",
      "cycle.cancelar",
      "cycle.reabrir",
      "cycle.corrigir_periodo",
      "cycle.admissao.incluir",
    ]);

    const proibidos = [
      "actor_id",
      "actorId",
      "author_id",
      "authorId",
      "status",
      "capability",
      "role",
      "cargo",
      "funcao",
      "papel",
      "posicao_id",
      "unidade_id",
      "gestor_id",
      "reference_date",
      "p_payload_hash",
    ];
    for (const invocacao of invocacoes) {
      for (const proibido of proibidos) {
        expect(Object.keys(invocacao.corpo), proibido).not.toContain(proibido);
      }
      expect(invocacao.corpo.operation_id).toBe(OPERACAO);
      expect(invocacao.corpo.cycle_id).toBe(CICLO);
    }
  });

  it("admissão por matrícula envia a intenção (o UUID é resolvido na fronteira)", async () => {
    const { cliente, invocacoes } = clienteFalso({ data: { ok: true, resultado: {} } });
    await criarEdgeCiclos(cliente).incluirAdmissao({
      ...ENTRADA_BASE,
      motivo: "Admitido",
      matricula: "MAT-9",
    });

    expect(invocacoes[0]!.corpo.matricula).toBe("MAT-9");
    expect(invocacoes[0]!.corpo.collaborator_id).toBeUndefined();
  });
});

describe("F5-09 P7 — adapter da Edge `ciclos` (fail-closed)", () => {
  it("erro de transporte com corpo em `context` expõe código público", async () => {
    const { cliente } = clienteFalso({
      error: { context: { error: { code: "FORBIDDEN", message: "Você não tem permissão." } } },
    });
    const resultado = await criarEdgeCiclos(cliente).ativar(ENTRADA_BASE);

    expect(resultado).toEqual({
      ok: false,
      error: { code: "FORBIDDEN", message: "Você não tem permissão." },
    });
  });

  it("código desconhecido vira FORBIDDEN e mensagem ausente vira texto padrão", async () => {
    const { cliente } = clienteFalso({ data: { error: { code: "CODIGO_NOVO" } } });
    const resultado = await criarEdgeCiclos(cliente).reabrir({ ...ENTRADA_BASE, motivo: "x" });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("FORBIDDEN");
    expect(resultado.error.message).toBe("Operação de ciclo recusada.");
  });

  it("2xx fora do contrato NÃO é sucesso presumido", async () => {
    const { cliente } = clienteFalso({ data: { resultado: { version: 9 } } });
    const resultado = await criarEdgeCiclos(cliente).ativar(ENTRADA_BASE);

    expect(resultado).toEqual({
      ok: false,
      error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
    });
  });

  it("erro de transporte sem corpo é recusado", async () => {
    const { cliente } = clienteFalso({ error: {} });
    const resultado = await criarEdgeCiclos(cliente).cancelar({ ...ENTRADA_BASE, motivo: "x" });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.error.code).toBe("FORBIDDEN");
  });

  it("projeções de erro ricas preservam o código público e a mensagem da Edge", async () => {
    const { cliente } = clienteFalso({
      data: { error: { code: "CONFLICT", message: "Operação recusada pelo estado atual do ciclo." } },
    });
    const resultado = await criarEdgeCiclos(cliente).encerrar({ ...ENTRADA_BASE, motivo: "x" });

    expect(resultado).toEqual({
      ok: false,
      error: { code: "CONFLICT", message: "Operação recusada pelo estado atual do ciclo." },
    });
  });
});
