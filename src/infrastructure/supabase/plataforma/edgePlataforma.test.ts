import { describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  OPERACAO_OPERADOR_ATUAL,
  OPERACAO_PROVISIONAR_ORGANIZACAO,
} from "./contrato";
import {
  FUNCAO_PLATAFORMA,
  corpoDaProvisao,
  criarEdgePlataforma,
  type RespostaEdgePlataforma,
} from "./edgePlataforma";

/**
 * F6-A03 (Issue #266) — adapter de cliente da Edge `provisionar-organizacao`.
 *
 * Prova que o cliente envia apenas INTENÇÃO, que a identificação do primeiro
 * Admin viaja em UMA única forma e que a resposta é FAIL-CLOSED nos TRÊS
 * caminhos: `error` de transporte, `error` no corpo 2xx e `data.ok !== true`
 * (2xx fora do contrato). Código desconhecido NUNCA vira sucesso: vira
 * `INTERNAL` (critério 25).
 *
 * F6-A11 (Issue #273): a identidade FUNCIONAL mínima do primeiro Admin
 * (`founder_full_name` e `founder_matricula`, D23/D26/D28) viaja SEMPRE — nas
 * DUAS formas de identificação — porque o bootstrap só conclui com a âncora
 * funcional do primeiro Admin.
 */

const OPERACAO_ID = "66666666-6666-4666-8666-666666666666";
const FOUNDER_ID = "77777777-7777-4777-8777-777777777777";
/** Dados FICTÍCIOS da identidade funcional mínima do primeiro Admin (F6-A11). */
const NOME_ADMIN = "Admin Teste A11";
const MATRICULA_ADMIN = "A1100001";

interface Invocacao {
  readonly funcao: string;
  readonly corpo: Record<string, unknown>;
}

interface ClienteFalso {
  readonly cliente: SupabaseClient;
  readonly invocacoes: Invocacao[];
  readonly proibidas: string[];
}

function clienteFalso(resposta: {
  data?: RespostaEdgePlataforma | null;
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
      throw new Error("o adapter de plataforma NAO pode ler tabela");
    },
    rpc: () => {
      proibidas.push("rpc");
      throw new Error("o browser NAO pode chamar RPC do banco");
    },
  } as unknown as SupabaseClient;
  return { cliente, invocacoes, proibidas };
}

describe("F6-A03 — adapter: corpo transportado", () => {
  it("envia operacao + operation_id + nome + identidade funcional do Admin, sem campo de autoridade", () => {
    const corpo = corpoDaProvisao({
      operationId: OPERACAO_ID,
      organizationName: "Org Sintetica",
      founderFullName: NOME_ADMIN,
      founderMatricula: MATRICULA_ADMIN,
      founderUserId: FOUNDER_ID,
    });

    expect(Object.keys(corpo).sort()).toEqual(
      [
        "founder_user_id",
        "founder_full_name",
        "founder_matricula",
        "operacao",
        "operation_id",
        "organization_name",
      ].sort()
    );
    expect(corpo.operacao).toBe(OPERACAO_PROVISIONAR_ORGANIZACAO);
    expect(corpo.organization_name).toBe("Org Sintetica");
    expect(corpo.founder_full_name).toBe(NOME_ADMIN);
    expect(corpo.founder_matricula).toBe(MATRICULA_ADMIN);
    expect(JSON.stringify(corpo)).not.toContain("organization_id");
    expect(JSON.stringify(corpo)).not.toContain("actor_user_profile_id");
    expect(JSON.stringify(corpo)).not.toContain("capability");
  });

  it("a identificação do primeiro Admin viaja em UMA única forma", () => {
    const porId = corpoDaProvisao({
      operationId: OPERACAO_ID,
      organizationName: "Org A",
      founderFullName: NOME_ADMIN,
      founderMatricula: MATRICULA_ADMIN,
      founderUserId: FOUNDER_ID,
    });
    expect(porId.founder_user_id).toBe(FOUNDER_ID);
    expect(Object.prototype.hasOwnProperty.call(porId, "founder_email")).toBe(false);

    const porEmail = corpoDaProvisao({
      operationId: OPERACAO_ID,
      organizationName: "Org B",
      founderFullName: NOME_ADMIN,
      founderMatricula: MATRICULA_ADMIN,
      founderEmail: "novo.admin@example.invalid",
    });
    expect(porEmail.founder_email).toBe("novo.admin@example.invalid");
    expect(Object.prototype.hasOwnProperty.call(porEmail, "founder_user_id")).toBe(false);
  });

  it("inclui founder_full_name e founder_matricula nas DUAS formas (F6-A11/D26)", () => {
    const porId = corpoDaProvisao({
      operationId: OPERACAO_ID,
      organizationName: "Org A",
      founderFullName: NOME_ADMIN,
      founderMatricula: MATRICULA_ADMIN,
      founderUserId: FOUNDER_ID,
    });
    const porEmail = corpoDaProvisao({
      operationId: OPERACAO_ID,
      organizationName: "Org B",
      founderFullName: NOME_ADMIN,
      founderMatricula: MATRICULA_ADMIN,
      founderEmail: "outro.admin@example.invalid",
    });

    for (const [forma, corpo] of [
      ["eu mesmo (founder_user_id)", porId],
      ["outra pessoa (founder_email)", porEmail],
    ] as const) {
      // As duas chaves novas viajam SEMPRE — nenhuma forma as omite.
      expect(Object.prototype.hasOwnProperty.call(corpo, "founder_full_name"), forma).toBe(true);
      expect(Object.prototype.hasOwnProperty.call(corpo, "founder_matricula"), forma).toBe(true);
      expect(corpo.founder_full_name, forma).toBe(NOME_ADMIN);
      expect(corpo.founder_matricula, forma).toBe(MATRICULA_ADMIN);
    }

    // Exatamente 6 chaves em cada forma: 4 fixas + a chave do Admin + a nova.
    expect(Object.keys(porId).sort()).toEqual(
      [
        "operacao",
        "operation_id",
        "organization_name",
        "founder_user_id",
        "founder_full_name",
        "founder_matricula",
      ].sort()
    );
    expect(Object.keys(porEmail).sort()).toEqual(
      [
        "operacao",
        "operation_id",
        "organization_name",
        "founder_email",
        "founder_full_name",
        "founder_matricula",
      ].sort()
    );
  });

  it("o self-check envia apenas a operação", async () => {
    const { cliente, invocacoes } = clienteFalso({ data: { ok: true, resultado: { operador: true } } });
    await criarEdgePlataforma(cliente).operadorAtual();

    expect(invocacoes).toHaveLength(1);
    expect(invocacoes[0].funcao).toBe(FUNCAO_PLATAFORMA);
    expect(Object.keys(invocacoes[0].corpo)).toEqual(["operacao"]);
    expect(invocacoes[0].corpo.operacao).toBe(OPERACAO_OPERADOR_ATUAL);
  });
});

describe("F6-A03 — adapter: fail-closed nos três caminhos", () => {
  it("sucesso exige `ok === true` E a chave `resultado`", async () => {
    const { cliente } = clienteFalso({
      data: { ok: true, operacao: OPERACAO_PROVISIONAR_ORGANIZACAO, resultado: { organization_id: "o-1" } },
    });
    const resposta = await criarEdgePlataforma(cliente).provisionarOrganizacao({
      operationId: OPERACAO_ID,
      organizationName: "Org",
      founderFullName: NOME_ADMIN,
      founderMatricula: MATRICULA_ADMIN,
      founderUserId: FOUNDER_ID,
    });
    expect(resposta.ok).toBe(true);
    if (resposta.ok) expect(resposta.data).toEqual({ organization_id: "o-1" });
  });

  it("2xx sem `ok: true` ou sem `resultado` ⇒ INTERNAL (nunca sucesso presumido)", async () => {
    for (const data of [
      { operacao: OPERACAO_PROVISIONAR_ORGANIZACAO, resultado: { organization_id: "o-1" } },
      { ok: "true", resultado: { organization_id: "o-1" } },
      { ok: true },
    ] as RespostaEdgePlataforma[]) {
      const { cliente } = clienteFalso({ data });
      const resposta = await criarEdgePlataforma(cliente).provisionarOrganizacao({
        operationId: OPERACAO_ID,
        organizationName: "Org",
        founderFullName: NOME_ADMIN,
        founderMatricula: MATRICULA_ADMIN,
        founderUserId: FOUNDER_ID,
      });
      expect(resposta.ok).toBe(false);
      if (!resposta.ok) expect(resposta.error.code).toBe("INTERNAL");
    }
  });

  it("erro de transporte lê o corpo público (`Response`) e mantém a lista fechada", async () => {
    const { cliente } = clienteFalso({
      error: { context: { json: async () => ({ error: { code: "NOT_AUTHORIZED", message: "x" } }) } },
    });
    const resposta = await criarEdgePlataforma(cliente).provisionarOrganizacao({
      operationId: OPERACAO_ID,
      organizationName: "Org",
      founderFullName: NOME_ADMIN,
      founderMatricula: MATRICULA_ADMIN,
      founderUserId: FOUNDER_ID,
    });
    expect(resposta.ok).toBe(false);
    if (!resposta.ok) expect(resposta.error.code).toBe("NOT_AUTHORIZED");
  });

  it("erro no corpo 2xx é respeitado e código DESCONHECIDO vira INTERNAL", async () => {
    const conhecido = clienteFalso({ data: { error: { code: "USER_EXISTS" } } });
    const r1 = await criarEdgePlataforma(conhecido.cliente).provisionarOrganizacao({
      operationId: OPERACAO_ID,
      organizationName: "Org",
      founderFullName: NOME_ADMIN,
      founderMatricula: MATRICULA_ADMIN,
      founderUserId: FOUNDER_ID,
    });
    expect(r1.ok).toBe(false);
    if (!r1.ok) expect(r1.error.code).toBe("USER_EXISTS");

    const desconhecido = clienteFalso({ data: { error: { code: "CODIGO_NOVO_DA_EDGE" } } });
    const r2 = await criarEdgePlataforma(desconhecido.cliente).provisionarOrganizacao({
      operationId: OPERACAO_ID,
      organizationName: "Org",
      founderFullName: NOME_ADMIN,
      founderMatricula: MATRICULA_ADMIN,
      founderUserId: FOUNDER_ID,
    });
    expect(r2.ok).toBe(false);
    if (!r2.ok) expect(r2.error.code).toBe("INTERNAL");
  });

  it("não lê tabela nem chama RPC do banco em caminho nenhum", async () => {
    const { cliente, proibidas } = clienteFalso({ data: { ok: true, resultado: { operador: false } } });
    const edge = criarEdgePlataforma(cliente);
    await edge.operadorAtual();
    await edge.provisionarOrganizacao({
      operationId: OPERACAO_ID,
      organizationName: "Org",
      founderFullName: NOME_ADMIN,
      founderMatricula: MATRICULA_ADMIN,
      founderUserId: FOUNDER_ID,
    });
    expect(proibidas).toEqual([]);
  });
});
