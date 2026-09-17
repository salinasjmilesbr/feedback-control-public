import { describe, expect, it } from "vitest";
import {
  codigoPublicoDeErroRpc,
  plataforma,
  reconhecerOperacaoAplicada,
  type DepsPlataforma,
  type ErroExecucao,
  type ExecucaoProvisionamento,
  type OperacaoAplicadaRegistrada,
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
 * - **reconhece o REPLAY do caminho por E-MAIL antes de qualquer convite** (o
 *   defeito corrigido: convidar primeiro devolvia `USER_EXISTS` no retry e
 *   quebrava a idempotência ponta a ponta);
 * - compensa o usuário criado no Auth quando a RPC falha — e a falha DESSA
 *   compensação não mascara o código público real;
 * - mapeia o erro da RPC para um código público FECHADO.
 */

const OPERADOR = "f6a30000-0000-4000-8000-000000000003";
const FOUNDER = "f6a30000-0000-4000-8000-000000000002";
const OPERACAO_ID = "f6a3b000-0000-4000-8000-000000000001";
const ORGANIZACAO = "f6a30000-0000-4000-8000-0000000000f1";
const EMAIL = "novo.admin@example.invalid";

interface Chamadas {
  readonly ordem: string[];
  readonly convidar: string[];
  readonly provisionar: ExecucaoProvisionamento[];
  readonly compensar: string[];
}

interface Cenario {
  readonly deps: DepsPlataforma;
  readonly chamadas: Chamadas;
  readonly resolveram: string[];
}

function cenario(
  opcoes: {
    caller?: string | null;
    operador?: boolean;
    aplicada?: OperacaoAplicadaRegistrada | null;
    convite?: ResultadoConvite;
    provisao?: ResultadoProvisionamento;
    operadorLanca?: boolean;
    compensarLanca?: boolean;
  } = {}
): Cenario {
  const chamadas: Chamadas = { ordem: [], convidar: [], provisionar: [], compensar: [] };
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
    operacaoAplicada: async () => {
      chamadas.ordem.push("consulta");
      return opcoes.aplicada ?? null;
    },
    convidarFounder: async (email) => {
      chamadas.ordem.push("convite");
      chamadas.convidar.push(email);
      return (
        opcoes.convite ?? {
          userId: "f6a30000-0000-4000-8000-0000000000aa",
          existente: false,
          erro: null,
        }
      );
    },
    provisionar: async (execucao) => {
      chamadas.ordem.push("provisao");
      chamadas.provisionar.push(execucao);
      return opcoes.provisao ?? { organizationId: ORGANIZACAO, erro: null };
    },
    compensarFounder: async (userId) => {
      chamadas.ordem.push("compensacao");
      chamadas.compensar.push(userId);
      if (opcoes.compensarLanca) throw new Error("deleteUser indisponível");
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

function corpoProvisaoPorEmail(email = EMAIL): Record<string, unknown> {
  const corpo = corpoProvisao({ founder_email: email });
  delete corpo.founder_user_id;
  return corpo;
}

/** Registro da âncora como a Edge o enxerga (intenção da 1ª execução). */
function aplicada(extra: Partial<OperacaoAplicadaRegistrada> = {}): OperacaoAplicadaRegistrada {
  return {
    organizationId: ORGANIZACAO,
    actorUserProfileId: OPERADOR,
    organizationName: "Org Sintetica F6-A03",
    founderUserId: FOUNDER,
    founderEmail: EMAIL,
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
    const r2 = await plataforma(
      requisicao({ operacao: "plataforma.listar_organizacoes" }),
      desconhecida.deps
    );
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
    const corpo = (await resposta.json()) as { resultado: { operador: boolean } };
    expect(corpo.resultado.operador).toBe(false);
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

  it("founder_user_id: NÃO consulta a âncora, NÃO convida e usa o ator VERIFICADO", async () => {
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
    // Caminho por identidade declarada: a âncora é resolvida pela própria RPC.
    expect(chamadas.ordem).toEqual(["provisao"]);
    expect(chamadas.provisionar).toHaveLength(1);
    expect(chamadas.provisionar[0]).toEqual({
      operationId: OPERACAO_ID,
      organizationName: "Org Sintetica F6-A03",
      founderUserId: FOUNDER,
      actorUserProfileId: OPERADOR,
    });
  });

  it("founder_email (operação NOVA): consulta a âncora ANTES de convidar, depois provisiona", async () => {
    const { deps, chamadas } = cenario({
      convite: { userId: "f6a30000-0000-4000-8000-0000000000cc", existente: false, erro: null },
    });

    const resposta = await plataforma(requisicao(corpoProvisaoPorEmail()), deps);
    expect(resposta.status).toBe(200);
    // ORDEM PROVADA: a âncora é consultada antes do efeito colateral no Auth.
    expect(chamadas.ordem).toEqual(["consulta", "convite", "provisao"]);
    expect(chamadas.convidar).toEqual([EMAIL]);
    expect(chamadas.provisionar[0].founderUserId).toBe("f6a30000-0000-4000-8000-0000000000cc");
    expect(chamadas.compensar).toEqual([]);
  });

  it("e-mail já existente em operação NOVA ⇒ USER_EXISTS sem provisionar nem compensar", async () => {
    const { deps, chamadas } = cenario({
      convite: { userId: null, existente: true, erro: null },
    });

    const resposta = await plataforma(
      requisicao(corpoProvisaoPorEmail("ja.existe@example.invalid")),
      deps
    );
    expect(resposta.status).toBe(409);
    expect(((await resposta.json()) as { error: { code: string } }).error.code).toBe("USER_EXISTS");
    expect(chamadas.ordem).toEqual(["consulta", "convite"]);
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

    const resposta = await plataforma(requisicao(corpoProvisaoPorEmail()), deps);
    expect(resposta.status).toBe(409);
    expect(((await resposta.json()) as { error: { code: string } }).error.code).toBe(
      "OPERATION_ALREADY_APPLIED"
    );
    expect(chamadas.compensar).toEqual(["f6a30000-0000-4000-8000-0000000000cc"]);
  });

  it("falha da COMPENSAÇÃO não mascara o código público real (best-effort local)", async () => {
    const { deps, chamadas } = cenario({
      convite: { userId: "f6a30000-0000-4000-8000-0000000000cc", existente: false, erro: null },
      provisao: {
        organizationId: null,
        erro: { code: "P0001", message: "F6_A03_CONFLICT: operation_id ja utilizado" },
      },
      compensarLanca: true,
    });

    const resposta = await plataforma(requisicao(corpoProvisaoPorEmail()), deps);
    // Nem 500 nem código de transporte: o veredito da operação prevalece.
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

describe("F6-A03 — Edge core: REPLAY REAL do caminho por e-mail (defeito corrigido)", () => {
  it("mesma intenção ⇒ devolve o MESMO organization_id SEM convidar de novo", async () => {
    const { deps, chamadas } = cenario({
      // A RPC responde como REPLAY: mesmo organization_id da 1ª execução.
      provisao: { organizationId: ORGANIZACAO, erro: null },
      aplicada: aplicada(),
    });

    const resposta = await plataforma(requisicao(corpoProvisaoPorEmail()), deps);

    expect(resposta.status).toBe(200);
    expect(await resposta.json()).toEqual({
      ok: true,
      operacao: OPERACAO_PROVISIONAR_ORGANIZACAO,
      resultado: { organization_id: ORGANIZACAO },
    });
    // NENHUM efeito colateral no Auth: o convite não é repetido.
    expect(chamadas.convidar).toEqual([]);
    // A ordem prova a correção: consulta → provisão (nunca convite).
    expect(chamadas.ordem).toEqual(["consulta", "provisao"]);
    // A RPC recebe o founder da PRIMEIRA execução (é o que reproduz o hash).
    expect(chamadas.provisionar).toEqual([
      {
        operationId: OPERACAO_ID,
        organizationName: "Org Sintetica F6-A03",
        founderUserId: FOUNDER,
        actorUserProfileId: OPERADOR,
      },
    ]);
    expect(chamadas.compensar).toEqual([]);
  });

  it("a identidade do replay é comparada sem diferenciar caixa/espaços do e-mail", async () => {
    const { deps, chamadas } = cenario({ aplicada: aplicada() });
    const resposta = await plataforma(
      requisicao(corpoProvisaoPorEmail("  Novo.Admin@Example.INVALID  ")),
      deps
    );
    expect(resposta.status).toBe(200);
    expect(chamadas.convidar).toEqual([]);
    expect(chamadas.ordem).toEqual(["consulta", "provisao"]);
  });

  it("intenção DIVERGENTE ⇒ OPERATION_ALREADY_APPLIED, sem convidar e sem executar", async () => {
    const divergentes: readonly Partial<OperacaoAplicadaRegistrada>[] = [
      { founderEmail: "outro.admin@example.invalid" },
      { founderEmail: null },
      { actorUserProfileId: "f6a30000-0000-4000-8000-0000000000ff" },
      { organizationName: "Outro nome" },
    ];

    for (const divergente of divergentes) {
      const { deps, chamadas } = cenario({ aplicada: aplicada(divergente) });
      const resposta = await plataforma(requisicao(corpoProvisaoPorEmail()), deps);

      expect(resposta.status, JSON.stringify(divergente)).toBe(409);
      expect(
        ((await resposta.json()) as { error: { code: string } }).error.code,
        JSON.stringify(divergente)
      ).toBe("OPERATION_ALREADY_APPLIED");
      expect(chamadas.convidar, JSON.stringify(divergente)).toEqual([]);
      expect(chamadas.provisionar, JSON.stringify(divergente)).toHaveLength(0);
      expect(chamadas.ordem, JSON.stringify(divergente)).toEqual(["consulta"]);
    }
  });
});

describe("F6-A03 — Edge core: reconhecimento puro da operação aplicada", () => {
  it("sem operação registrada ⇒ `nenhum`", () => {
    expect(
      reconhecerOperacaoAplicada(null, {
        actorUserProfileId: OPERADOR,
        organizationName: "Org Sintetica F6-A03",
        founderEmail: EMAIL,
      })
    ).toEqual({ tipo: "nenhum" });
  });

  it("mesma intenção ⇒ `replay` com o founder da primeira execução", () => {
    expect(
      reconhecerOperacaoAplicada(aplicada(), {
        actorUserProfileId: OPERADOR,
        organizationName: "Org Sintetica F6-A03",
        founderEmail: EMAIL,
      })
    ).toEqual({ tipo: "replay", founderUserId: FOUNDER });
  });

  it("qualquer divergência (ou e-mail não resolvido) ⇒ `divergente` (fail-closed)", () => {
    const intencao = {
      actorUserProfileId: OPERADOR,
      organizationName: "Org Sintetica F6-A03",
      founderEmail: EMAIL,
    };
    for (const registro of [
      aplicada({ founderEmail: null }),
      aplicada({ founderEmail: "outro@example.invalid" }),
      aplicada({ actorUserProfileId: "outro-ator" }),
      aplicada({ organizationName: "Outro nome" }),
    ]) {
      expect(reconhecerOperacaoAplicada(registro, intencao), JSON.stringify(registro)).toEqual({
        tipo: "divergente",
      });
    }
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
