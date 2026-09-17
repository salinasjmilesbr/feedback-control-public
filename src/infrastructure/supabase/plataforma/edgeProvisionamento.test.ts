import { describe, expect, it } from "vitest";
import {
  codigoPublicoDeErroRpc,
  plataforma,
  type DepsPlataforma,
  type ErroExecucao,
  type ExecucaoProvisionamento,
  type ResultadoConvite,
  type ResultadoProvisionamento,
} from "../../../../supabase/functions/provisionar-organizacao/core.ts";
import {
  OPERACAO_OPERADOR_ATUAL,
  OPERACAO_PROVISIONAR_ORGANIZACAO,
} from "./contrato";

/**
 * F6-A03 (Issue #266) — núcleo da Edge `provisionar-organizacao`.
 *
 * Prova, sem runtime Deno e sem rede, que a fronteira:
 * - resolve a identidade ANTES de decidir conteúdo e nunca aceita ator do corpo;
 * - aplica a AUTORIDADE DE PLATAFORMA (fora do corpo) e não vaza validação de
 *   forma para quem não é operador;
 * - no self-check NUNCA responde 403 e é fail-closed (`operador: false`);
 * - compensa o usuário criado no Auth quando a RPC falha;
 * - mapeia o erro da RPC para um código público FECHADO.
 */

const OPERADOR = "f6a30000-0000-4000-8000-000000000003";
const FOUNDER = "f6a30000-0000-4000-8000-000000000002";
const OPERACAO_ID = "f6a3b000-0000-4000-8000-000000000001";
const ORGANIZACAO = "f6a30000-0000-4000-8000-0000000000f1";

interface Chamadas {
  readonly convidar: string[];
  readonly provisionar: ExecucaoProvisionamento[];
  readonly compensar: string[];
}

interface Cenario {
  readonly deps: DepsPlataforma;
  readonly chamadas: Chamadas;
  readonly resolveram: string[];
}

function cenario(opcoes: {
  caller?: string | null;
  operador?: boolean;
  convite?: ResultadoConvite;
  provisao?: ResultadoProvisionamento;
  operadorLanca?: boolean;
} = {}): Cenario {
  const chamadas: Chamadas = { convidar: [], provisionar: [], compensar: [] };
  const resolveram: string[] = [];

  const deps: DepsPlataforma = {
    resolveCaller: async (header) => {
      resolveram.push(header ?? "");
      return opcoes.caller === undefined ? OPERADOR : opcoes.caller;
    },
    operadorAutorizado: async () => {
      if (opcoes.operadorLanca) throw new Error("falha de rede");
      return opcoes.operador ?? true;
    },
    convidarFounder: async (email) => {
      chamadas.convidar.push(email);
      return (
        opcoes.convite ?? { userId: "f6a30000-0000-4000-8000-0000000000aa", existente: false, erro: null }
      );
    },
    provisionar: async (execucao) => {
      chamadas.provisionar.push(execucao);
      return opcoes.provisao ?? { organizationId: ORGANIZACAO, erro: null };
    },
    compensarFounder: async (userId) => {
      chamadas.compensar.push(userId);
    },
  };

  return { deps, chamadas, resolveram };
}

function requisicao(corpo: unknown, metodo = "POST"): Request {
  return new Request("http://local/functions/v1/provisionar-organizacao", {
    method: metodo,
    headers: { "Content-Type": "application/json" },
    ...(metodo === "POST" ? { body: JSON.stringify(corpo) } : {}),
  });
}

function corpoProvisao(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    operacao: OPERACAO_PROVISIONAR_ORGANIZACAO,
    operation_id: OPERACAO_ID,
    organization_name: "Org Sintetica F6-A03",
    founder_user_id: FOUNDER,
    ...extra,
  };
}

describe("F6-A03 — Edge core: método e forma", () => {
  it("OPTIONS responde sem exigir identidade; método diferente de POST é 405", async () => {
    const { deps } = cenario();
    const preflight = await plataforma(requisicao({}, "OPTIONS"), deps);
    expect(preflight.status).toBe(200);

    const get = await plataforma(requisicao({}, "GET"), deps);
    expect(get.status).toBe(405);
    expect(await get.json()).toEqual({
      error: { code: "METHOD_NOT_ALLOWED", message: "Método não permitido." },
    });
  });

  it("corpo inválido e operação desconhecida ⇒ INVALID_INPUT ANTES de resolver identidade", async () => {
    const invalido = cenario();
    const semJson = new Request("http://local/x", { method: "POST", body: "{" });
    const r1 = await plataforma(semJson, invalido.deps);
    expect(r1.status).toBe(400);
    expect(invalido.resolveram).toHaveLength(0);

    const desconhecida = cenario();
    const r2 = await plataforma(requisicao({ operacao: "plataforma.listar_organizacoes" }), desconhecida.deps);
    expect(r2.status).toBe(400);
    expect(((await r2.json()) as { error: { code: string } }).error.code).toBe("INVALID_INPUT");
    expect(desconhecida.resolveram).toHaveLength(0);
  });

  it("sem JWT válido ⇒ 401 (nas duas operações)", async () => {
    for (const operacao of [OPERACAO_PROVISIONAR_ORGANIZACAO, OPERACAO_OPERADOR_ATUAL]) {
      const { deps } = cenario({ caller: null });
      const resposta = await plataforma(requisicao({ operacao }), deps);
      expect(resposta.status).toBe(401);
      expect(((await resposta.json()) as { error: { code: string } }).error.code).toBe(
        "NOT_AUTHORIZED"
      );
    }
  });
});

describe("F6-A03 — Edge core: self-check é UX, nunca autorização (D20)", () => {
  it("operador autorizado ⇒ { operador: true }", async () => {
    const { deps } = cenario({ operador: true });
    const resposta = await plataforma(requisicao({ operacao: OPERACAO_OPERADOR_ATUAL }), deps);
    expect(resposta.status).toBe(200);
    expect(await resposta.json()).toEqual({
      ok: true,
      operacao: OPERACAO_OPERADOR_ATUAL,
      resultado: { operador: true },
    });
  });

  it("não-operador ⇒ 200 com `operador: false` (nunca 403, sem dica)", async () => {
    const { deps } = cenario({ operador: false });
    const resposta = await plataforma(requisicao({ operacao: OPERACAO_OPERADOR_ATUAL }), deps);
    expect(resposta.status).toBe(200);
    expect(await resposta.json()).toEqual({
      ok: true,
      operacao: OPERACAO_OPERADOR_ATUAL,
      resultado: { operador: false },
    });
  });

  it("falha ao decidir autoridade ⇒ `operador: false` (fail-closed)", async () => {
    const { deps } = cenario({ operadorLanca: true });
    const resposta = await plataforma(requisicao({ operacao: OPERACAO_OPERADOR_ATUAL }), deps);
    expect(resposta.status).toBe(200);
    expect(((await resposta.json()) as { resultado: { operador: boolean } }).resultado.operador).toBe(
      false
    );
  });

  it("a forma é estrita: chave adicional ⇒ INVALID_INPUT", async () => {
    const { deps } = cenario();
    const resposta = await plataforma(
      requisicao({ operacao: OPERACAO_OPERADOR_ATUAL, organization_id: "x" }),
      deps
    );
    expect(resposta.status).toBe(400);
  });
});

describe("F6-A03 — Edge core: provisionamento", () => {
  it("não-operador ⇒ 403 e NENHUMA validação de forma é revelada", async () => {
    const { deps, chamadas } = cenario({ operador: false });
    const resposta = await plataforma(
      requisicao(corpoProvisao({ organization_id: "vazamento", version: 3 })),
      deps
    );
    expect(resposta.status).toBe(403);
    expect(((await resposta.json()) as { error: { code: string } }).error.code).toBe(
      "NOT_AUTHORIZED"
    );
    expect(chamadas.convidar).toHaveLength(0);
    expect(chamadas.provisionar).toHaveLength(0);
  });

  it("founder_user_id: NÃO convida e usa o ator VERIFICADO (nunca do corpo)", async () => {
    const { deps, chamadas } = cenario();
    const resposta = await plataforma(
      requisicao(corpoProvisao({ actor_user_profile_id: "intruso" })),
      deps
    );

    // Corpo com campo de autoridade ⇒ recusado ANTES de qualquer execução.
    expect(resposta.status).toBe(400);
    expect(chamadas.provisionar).toHaveLength(0);

    const ok = await plataforma(requisicao(corpoProvisao()), deps);
    expect(ok.status).toBe(200);
    expect(await ok.json()).toEqual({
      ok: true,
      operacao: OPERACAO_PROVISIONAR_ORGANIZACAO,
      resultado: { organization_id: ORGANIZACAO },
    });
    expect(chamadas.convidar).toEqual([]);
    expect(chamadas.provisionar).toHaveLength(1);
    expect(chamadas.provisionar[0]).toEqual({
      operationId: OPERACAO_ID,
      organizationName: "Org Sintetica F6-A03",
      founderUserId: FOUNDER,
      actorUserProfileId: OPERADOR,
    });
  });

  it("founder_email: convida e provisiona com a identidade CRIADA", async () => {
    const { deps, chamadas } = cenario({
      convite: { userId: "f6a30000-0000-4000-8000-0000000000cc", existente: false, erro: null },
    });
    const corpo = corpoProvisao({ founder_email: "Novo.Admin@Example.INVALID" });
    delete corpo.founder_user_id;

    const resposta = await plataforma(requisicao(corpo), deps);
    expect(resposta.status).toBe(200);
    expect(chamadas.convidar).toEqual(["novo.admin@example.invalid"]);
    expect(chamadas.provisionar[0].founderUserId).toBe("f6a30000-0000-4000-8000-0000000000cc");
    expect(chamadas.compensar).toEqual([]);
  });

  it("e-mail já existente ⇒ USER_EXISTS sem provisionar nem compensar", async () => {
    const { deps, chamadas } = cenario({
      convite: { userId: null, existente: true, erro: null },
    });
    const corpo = corpoProvisao({ founder_email: "ja.existe@example.invalid" });
    delete corpo.founder_user_id;

    const resposta = await plataforma(requisicao(corpo), deps);
    expect(resposta.status).toBe(409);
    expect(((await resposta.json()) as { error: { code: string } }).error.code).toBe("USER_EXISTS");
    expect(chamadas.provisionar).toHaveLength(0);
    expect(chamadas.compensar).toEqual([]);
  });

  it("falha da RPC COMPENSA o usuário recém-criado e devolve código público fechado", async () => {
    const { deps, chamadas } = cenario({
      convite: { userId: "f6a30000-0000-4000-8000-0000000000cc", existente: false, erro: null },
      provisao: {
        organizationId: null,
        erro: { code: "P0001", message: "F6_A03_CONFLICT: operation_id ja utilizado" },
      },
    });
    const corpo = corpoProvisao({ founder_email: "novo.admin@example.invalid" });
    delete corpo.founder_user_id;

    const resposta = await plataforma(requisicao(corpo), deps);
    expect(resposta.status).toBe(409);
    expect(((await resposta.json()) as { error: { code: string } }).error.code).toBe(
      "OPERATION_ALREADY_APPLIED"
    );
    expect(chamadas.compensar).toEqual(["f6a30000-0000-4000-8000-0000000000cc"]);
  });

  it("erro desconhecido do executor ⇒ INTERNAL (sem vazar detalhe)", async () => {
    const { deps } = cenario({
      provisao: { organizationId: null, erro: { code: "XX000", message: "detalhe interno" } },
    });
    const resposta = await plataforma(requisicao(corpoProvisao()), deps);
    expect(resposta.status).toBe(500);
    const corpo = (await resposta.json()) as { error: { code: string; message: string } };
    expect(corpo.error.code).toBe("INTERNAL");
    expect(corpo.error.message).not.toContain("detalhe interno");
  });

  it("resposta sem organization_id não vira sucesso", async () => {
    const { deps } = cenario({ provisao: { organizationId: null, erro: null } });
    const resposta = await plataforma(requisicao(corpoProvisao()), deps);
    expect(resposta.status).toBe(500);
  });
});

describe("F6-A03 — Edge core: mapa fechado de erro da RPC", () => {
  it("mapeia os prefixos da RPC e as classes do Postgres", () => {
    const casos: readonly (readonly [ErroExecucao | null, string])[] = [
      [null, "INTERNAL"],
      [{ message: "F6_A03_FORBIDDEN: perfil do operador" }, "NOT_AUTHORIZED"],
      [{ message: "F6_A03_INVALID_NAME: nome obrigatorio" }, "INVALID_NAME"],
      [{ message: "F6_A03_INVALID_FOUNDER: inexistente" }, "INVALID_FOUNDER"],
      [{ message: "F6_A03_INVALID_INPUT: operation_id" }, "INVALID_INPUT"],
      [{ message: "F6_A03_CONFLICT: operation_id ja utilizado" }, "OPERATION_ALREADY_APPLIED"],
      [{ message: "F6_A03_INTERNAL: membership nao persistida" }, "INTERNAL"],
      [{ code: "23503", message: "fk" }, "INVALID_FOUNDER"],
      [{ code: "23502", message: "not null" }, "INVALID_INPUT"],
      [{ code: "23514", message: "check" }, "INVALID_INPUT"],
      [{ code: "23505", message: "unique" }, "OPERATION_ALREADY_APPLIED"],
      [{ code: "42501", message: "permission denied" }, "INTERNAL"],
    ];
    for (const [erro, esperado] of casos) {
      expect(codigoPublicoDeErroRpc(erro), JSON.stringify(erro)).toBe(esperado);
    }
  });
});
