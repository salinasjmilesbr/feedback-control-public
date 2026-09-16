import { describe, expect, it } from "vitest";
import {
  codigoDeErroRpc,
  observacoes,
  type AlvoFuncionalObservacao,
  type DepsObservacoes,
  type ExecucaoObservacao,
  type ResultadoRpcObservacao,
} from "../../supabase/functions/observacoes/core.ts";
import type { AuthIdentity } from "../auth/tipos.ts";
import type { CodigoPublico } from "../infrastructure/supabase/observacoes/contrato.ts";

/**
 * F5-11 P4 (Issue #248) — fronteira soberana de OBSERVAÇÕES na Edge.
 *
 * Prova, com o núcleo REAL da Edge (`observacoes(req, deps)`, não mockado) e
 * dependências sintéticas, a ordem normativa e o fail-closed:
 * método → JWT (`auth.getUser`) → forma (allowlist estrita) → tenant revalidado →
 * gate por operação → RPC privilegiada. A RPC NUNCA é chamada antes da decisão; o
 * ator é SEMPRE o `auth.uid` verificado (nunca do corpo); o alvo funcional vem de
 * mapa FECHADO por operação (`observation` existente ou `collaborator` na criação);
 * a listagem por escopo é o ÚNICO plano ADMINISTRATIVO (§8 linha 1) e não manda
 * alvo ao engine; erro da RPC só vira código público pelos prefixos `F5_11_*`;
 * mensagem crua do banco não vaza.
 *
 * Nota de vocabulário (espelho do molde `metasEdge.test.ts`): no NÚCLEO um erro
 * SEM prefixo conhecido é `INTERNAL` (a fronteira nunca inventa conflito de
 * domínio); a conversão de código DESCONHECIDO em `FORBIDDEN` é regra do ADAPTER
 * de cliente (`edgeObservacoes.ts`), coberta em `edgeObservacoes.test.ts`.
 *
 * Nenhum dado real: todos os identificadores são UUID sintéticos.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const USER = "33333333-3333-4333-8333-333333333333";
const USER_B = "44444444-4444-4444-8444-444444444444";
const CICLO = "55555555-5555-4555-8555-555555555555";
const OPERACAO = "66666666-6666-4666-8666-666666666666";
const COLABORADOR = "77777777-7777-4777-8777-777777777777";
const OBSERVACAO = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const URL_EDGE = "https://edge.local/functions/v1/observacoes";

interface CorpoErro {
  readonly error?: { readonly code?: string; readonly message?: string };
}
interface CorpoSucesso {
  readonly ok?: boolean;
  readonly operacao?: string;
  readonly resultado?: unknown;
}

function identidade(authUserId: string = USER, overrides: Partial<AuthIdentity> = {}): AuthIdentity {
  return {
    authUserId,
    perfil: { id: authUserId, status: "active" },
    memberships: [{ id: "m-1", organizationId: ORG, status: "active" }],
    organizacoes: [{ id: ORG, name: "Organizacao sintetica" }],
    ...overrides,
  } as unknown as AuthIdentity;
}

/**
 * Corpo VÁLIDO por operação, montado a partir da FORMA contratada (allowlist do
 * contrato: nada de autoria/tenant/estado/instante). É a base das provas de gate e
 * de execução; a recusa de uma chave proibida é sempre atribuível só a ela.
 */
function corpo(operacao: string): Record<string, unknown> {
  const comum = { organization_id: ORG, operacao, operation_id: OPERACAO };
  switch (operacao) {
    case "observacao.criar":
      return {
        ...comum,
        cycle_id: CICLO,
        collaborator_id: COLABORADOR,
        tipo: "POSITIVA",
        texto: "Observacao sintetica de teste.",
      };
    case "observacao.editar":
      return {
        ...comum,
        observation_id: OBSERVACAO,
        tipo: "NEUTRA",
        texto: "Observacao sintetica editada.",
        comunicado: true,
        expected_version: 0,
      };
    case "observacao.definir_comunicado":
      return { ...comum, observation_id: OBSERVACAO, comunicado: true, expected_version: 0 };
    case "observacao.excluir":
    case "observacao.revogar":
      return {
        ...comum,
        observation_id: OBSERVACAO,
        motivo: "Motivo sintetico de teste.",
        expected_version: 0,
      };
    case "observacao.obter":
    case "observacao.historico":
      return { ...comum, observation_id: OBSERVACAO };
    case "observacao.listar_por_escopo":
      return { ...comum, escopo: "SELF" };
    default:
      return comum;
  }
}

/** Operações cujo alvo funcional é a OBSERVAÇÃO existente (§8). */
const OPERACOES_DE_LINHA = [
  "observacao.editar",
  "observacao.definir_comunicado",
  "observacao.excluir",
  "observacao.revogar",
  "observacao.obter",
  "observacao.historico",
] as const;

/** Capability exigida por operação funcional (mapa FECHADO do contrato). */
const CAPABILITY_ESPERADA: Readonly<Record<string, string>> = {
  "observacao.criar": "observation.create",
  "observacao.editar": "observation.edit",
  "observacao.definir_comunicado": "observation.edit",
  "observacao.excluir": "observation.delete",
  "observacao.revogar": "observation.edit",
  "observacao.obter": "observation.read",
  "observacao.historico": "observation.read",
};

interface Cenario {
  readonly identidade?: AuthIdentity | null;
  readonly capabilities?: readonly string[];
  readonly autorizacao?: { readonly permitido: boolean; readonly code?: CodigoPublico };
  readonly rpc?: ResultadoRpcObservacao;
}

interface GateChamado {
  readonly capability: string;
  readonly alvo: AlvoFuncionalObservacao;
  readonly cycleId: string | null | undefined;
}

interface Capturado {
  readonly gates: GateChamado[];
  readonly capabilities: { readonly actorUserProfileId: string; readonly organizationId: string }[];
  readonly execucoes: ExecucaoObservacao[];
}

function cenarioBase(): Capturado {
  return { gates: [], capabilities: [], execucoes: [] };
}

function deps(entrada: Cenario, capturado: Capturado): DepsObservacoes {
  return {
    resolveCaller: async (authHeader) =>
      authHeader === "Bearer ok" ? USER : authHeader === "Bearer ok2" ? USER_B : null,
    resolverIdentidade: async (authUserId) =>
      entrada.identidade === undefined ? identidade(authUserId) : entrada.identidade,
    resolverCapabilitiesEfetivas: async (pedido) => {
      capturado.capabilities.push(pedido);
      return (entrada.capabilities ?? []).map((capability_code) => ({ capability_code }));
    },
    avaliarAutorizacao: async ({ capability, alvo, cycleId }) => {
      capturado.gates.push({ capability, alvo, cycleId });
      return entrada.autorizacao ?? { permitido: true };
    },
    executarRpc: async (execucao) => {
      capturado.execucoes.push(execucao);
      return entrada.rpc ?? { data: { observation_id: OBSERVACAO, version: 1 } };
    },
  };
}

function pedido(
  corpoPedido: unknown,
  opcoes: { readonly method?: string; readonly auth?: string | null } = {}
): Request {
  const method = opcoes.method ?? "POST";
  const headers = new Headers();
  if (opcoes.auth !== null) headers.set("Authorization", opcoes.auth ?? "Bearer ok");
  const semCorpo = opcoes.method !== undefined && method !== "POST";
  return semCorpo
    ? new Request(URL_EDGE, { method, headers })
    : new Request(URL_EDGE, { method, headers, body: JSON.stringify(corpoPedido) });
}

async function executar(
  corpoPedido: unknown,
  entrada: Cenario = {},
  opcoes: { readonly method?: string; readonly auth?: string | null } = {}
): Promise<{ resposta: Response; capturado: Capturado }> {
  const capturado = cenarioBase();
  const resposta = await observacoes(pedido(corpoPedido, opcoes), deps(entrada, capturado));
  return { resposta, capturado };
}

describe("F5-11 P4 — ordem normativa da fronteira de observacoes", () => {
  it("A: OPTIONS responde 200 com CORS, sem exigir credencial", async () => {
    const { resposta, capturado } = await executar(null, {}, { method: "OPTIONS", auth: null });
    expect(resposta.status).toBe(200);
    expect(await resposta.text()).toBe("ok");
    expect(resposta.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(capturado.execucoes).toHaveLength(0);
  });

  it("B: método não-POST é 405 METHOD_NOT_ALLOWED e não toca a RPC", async () => {
    for (const method of ["PUT", "DELETE", "PATCH"]) {
      const { resposta, capturado } = await executar(corpo("observacao.obter"), {}, { method });
      expect(resposta.status, method).toBe(405);
      const devolvido = (await resposta.json()) as CorpoErro;
      expect(devolvido.error?.code, method).toBe("METHOD_NOT_ALLOWED");
      expect(capturado.execucoes, method).toHaveLength(0);
    }
  });

  it("C: POST sem header Authorization é 401 NOT_AUTHORIZED", async () => {
    const { resposta, capturado } = await executar(corpo("observacao.obter"), {}, { auth: null });
    expect(resposta.status).toBe(401);
    expect(((await resposta.json()) as CorpoErro).error?.code).toBe("NOT_AUTHORIZED");
    expect(capturado.execucoes).toHaveLength(0);
  });

  it("D: JWT que não resolve identidade soberana é 401 (nada é decidido nem executado)", async () => {
    const { resposta, capturado } = await executar(
      corpo("observacao.obter"),
      {},
      { auth: "Bearer invalido" }
    );
    expect(resposta.status).toBe(401);
    expect(((await resposta.json()) as CorpoErro).error?.code).toBe("NOT_AUTHORIZED");
    expect(capturado.gates).toHaveLength(0);
    expect(capturado.execucoes).toHaveLength(0);
  });

  it("E: corpo que não é JSON é 400 INVALID_INPUT (falha fechada antes do gate)", async () => {
    const capturado = cenarioBase();
    const resposta = await observacoes(
      new Request(URL_EDGE, {
        method: "POST",
        headers: { Authorization: "Bearer ok" },
        body: "{nao-e-json",
      }),
      deps({}, capturado)
    );
    expect(resposta.status).toBe(400);
    expect(((await resposta.json()) as CorpoErro).error?.code).toBe("INVALID_INPUT");
    expect(capturado.gates).toHaveLength(0);
    expect(capturado.execucoes).toHaveLength(0);
  });
});

describe("F5-11 P4 — forma é FORMA, nunca autoridade", () => {
  it("F: operação desconhecida ou de outro domínio é 400 (sem default permissivo)", async () => {
    for (const operacao of [
      "observacao.invalidar",
      "observacao.listar",
      "observation.criar",
      "meta.criar",
      "goal.criar",
      "",
    ]) {
      const { resposta, capturado } = await executar({ ...corpo("observacao.criar"), operacao });
      expect(resposta.status, operacao).toBe(400);
      expect(((await resposta.json()) as CorpoErro).error?.code, operacao).toBe("INVALID_INPUT");
      expect(capturado.gates, operacao).toHaveLength(0);
      expect(capturado.execucoes, operacao).toHaveLength(0);
    }
  });

  it("G: campos de identidade/autoridade/instante no corpo são 400 e a RPC não roda", async () => {
    const proibidos: readonly (readonly [string, unknown])[] = [
      ["actor_id", COLABORADOR],
      ["actor_user_profile_id", COLABORADOR],
      ["author_user_profile_id", USER],
      ["author_collaborator_id", COLABORADOR],
      ["membership_id", "m-1"],
      ["tenant_id", ORG],
      ["status", "ATIVO"],
      ["excluida", false],
      ["comunicado_em", "2026-04-01T00:00:00.000Z"],
      ["version", 1],
      ["payload_hash", "0".repeat(64)],
      ["capability", "observation.create"],
      ["scope", "DESCENDANTS"],
      ["role", "admin"],
      ["cargo", "Diretor"],
      ["funcao", "GERENTE"],
      ["papel", "GERENTE"],
      ["domainState", { comunicado: true }],
      ["data", "2026-04-01T00:00:00.000Z"],
      ["instante", "2026-04-01T00:00:00.000Z"],
    ];
    for (const [campo, valor] of proibidos) {
      const { resposta, capturado } = await executar({ ...corpo("observacao.criar"), [campo]: valor });
      expect(resposta.status, campo).toBe(400);
      expect(((await resposta.json()) as CorpoErro).error?.code, campo).toBe("INVALID_INPUT");
      expect(capturado.gates, campo).toHaveLength(0);
      expect(capturado.execucoes, campo).toHaveLength(0);
    }
  });

  it("H: campo de OUTRA operação é recusado (allowlist por operação)", async () => {
    for (const extra of [
      { cycle_id: CICLO },
      { collaborator_id: COLABORADOR },
      { observacao_id: OBSERVACAO },
    ]) {
      const { resposta } = await executar({ ...corpo("observacao.obter"), ...extra });
      expect(resposta.status, JSON.stringify(extra)).toBe(400);
    }
    for (const extra of [{ expected_version: 0 }, { motivo: "x" }, { observation_id: OBSERVACAO }]) {
      const { resposta } = await executar({ ...corpo("observacao.criar"), ...extra });
      expect(resposta.status, JSON.stringify(extra)).toBe(400);
    }
  });
});

describe("F5-11 P4 — tenant revalidado ANTES do gate", () => {
  it("I: organização sem membership ativa é 403 sem consultar o gate nem a RPC", async () => {
    const { resposta, capturado } = await executar({
      ...corpo("observacao.obter"),
      organization_id: ORG_B,
    });
    expect(resposta.status).toBe(403);
    expect(((await resposta.json()) as CorpoErro).error?.code).toBe("FORBIDDEN");
    expect(capturado.gates).toHaveLength(0);
    expect(capturado.execucoes).toHaveLength(0);
  });

  it("J: identidade ausente é 401 e membership inativa é 403 (sem tocar a RPC)", async () => {
    const semIdentidade = await executar(corpo("observacao.obter"), { identidade: null });
    expect(semIdentidade.resposta.status).toBe(401);
    expect(semIdentidade.capturado.execucoes).toHaveLength(0);

    const inativa = await executar(corpo("observacao.obter"), {
      identidade: identidade(USER, {
        memberships: [{ id: "m-1", organizationId: ORG, status: "disabled" }],
      }),
    });
    expect(inativa.resposta.status).toBe(403);
    expect(inativa.capturado.execucoes).toHaveLength(0);
  });
});

describe("F5-11 P4 — gate por operação (alvo REAL, mapa fechado)", () => {
  it("K: `observacao.criar` avalia `observation.create` sobre o COLABORADOR-alvo (com o ciclo da intenção)", async () => {
    const { resposta, capturado } = await executar(corpo("observacao.criar"));
    expect(resposta.status).toBe(200);
    expect(capturado.gates).toEqual([
      {
        capability: "observation.create",
        alvo: { type: "collaborator", id: COLABORADOR },
        cycleId: CICLO,
      },
    ]);
    // Plano ADMINISTRATIVO não foi usado: a criação decide no engine.
    expect(capturado.capabilities).toHaveLength(0);
    const execucao = capturado.execucoes[0];
    expect(execucao?.observationId).toBeNull();
    expect(execucao?.collaboratorId).toBe(COLABORADOR);
    expect(execucao?.cycleId).toBe(CICLO);
  });

  it("L: as SEIS operações de linha existente avaliam a OBSERVAÇÃO real e a capability do mapa", async () => {
    for (const operacao of OPERACOES_DE_LINHA) {
      const { resposta, capturado } = await executar(corpo(operacao));
      expect(resposta.status, operacao).toBe(200);
      expect(capturado.gates, operacao).toEqual([
        {
          capability: CAPABILITY_ESPERADA[operacao],
          alvo: { type: "observation", id: OBSERVACAO },
          cycleId: null,
        },
      ]);
      expect(capturado.execucoes[0]?.observationId, operacao).toBe(OBSERVACAO);
    }
  });

  it("M: negação do gate vira o código público e a RPC NÃO é chamada", async () => {
    const negado = await executar(corpo("observacao.obter"), {
      autorizacao: { permitido: false, code: "CONFLICT" },
    });
    expect(negado.resposta.status).toBe(409);
    expect(((await negado.resposta.json()) as CorpoErro).error?.code).toBe("CONFLICT");
    expect(negado.capturado.execucoes).toHaveLength(0);

    const semCodigo = await executar(corpo("observacao.obter"), {
      autorizacao: { permitido: false },
    });
    expect(semCodigo.resposta.status).toBe(403);
    expect(((await semCodigo.resposta.json()) as CorpoErro).error?.code).toBe("FORBIDDEN");
    expect(semCodigo.capturado.execucoes).toHaveLength(0);
  });

  it("N: `observacao.listar_por_escopo` é ADMINISTRATIVA — capability efetiva, sem alvo no engine", async () => {
    const semCapability = await executar(corpo("observacao.listar_por_escopo"), {
      capabilities: ["observation.write"],
    });
    expect(semCapability.resposta.status).toBe(403);
    expect(semCapability.capturado.gates).toHaveLength(0);
    expect(semCapability.capturado.execucoes).toHaveLength(0);
    expect(semCapability.capturado.capabilities).toEqual([
      { actorUserProfileId: USER, organizationId: ORG },
    ]);

    const comCapability = await executar(corpo("observacao.listar_por_escopo"), {
      capabilities: ["observation.read"],
    });
    expect(comCapability.resposta.status).toBe(200);
    expect(comCapability.capturado.gates).toHaveLength(0);
    const execucao = comCapability.capturado.execucoes[0];
    expect(execucao?.operacao).toBe("observacao.listar_por_escopo");
    expect(execucao?.escopo).toBe("SELF");
    expect(execucao?.observationId).toBeNull();
  });
});

describe("F5-11 P4 — execução privilegiada só pós-decisão, com o ator VERIFICADO", () => {
  it("O: sucesso devolve `{ok, operacao, resultado}` do payload cru da RPC", async () => {
    const { resposta } = await executar(corpo("observacao.criar"), {
      rpc: { data: { observation_id: OBSERVACAO, version: 1 } },
    });
    expect(resposta.status).toBe(200);
    const devolvido = (await resposta.json()) as CorpoSucesso;
    expect(devolvido.ok).toBe(true);
    expect(devolvido.operacao).toBe("observacao.criar");
    expect(devolvido.resultado).toEqual({ observation_id: OBSERVACAO, version: 1 });
  });

  it("P: o ator da RPC é o `auth.uid` VERIFICADO — o mesmo corpo com outro JWT muda o ator", async () => {
    const primeiro = await executar(corpo("observacao.obter"));
    expect(primeiro.capturado.execucoes[0]?.actorUserProfileId).toBe(USER);

    const segundo = await executar(corpo("observacao.obter"), {}, { auth: "Bearer ok2" });
    expect(segundo.capturado.execucoes[0]?.actorUserProfileId).toBe(USER_B);
    // Mesmo corpo, ator diferente: o identificador vem do token, nunca do corpo.
    expect(segundo.capturado.execucoes[0]?.actorUserProfileId).not.toBe(
      primeiro.capturado.execucoes[0]?.actorUserProfileId
    );
  });

  it("Q: a execução não carrega autoridade declarada nem instante do chamador", async () => {
    const { capturado } = await executar(corpo("observacao.criar"));
    const execucao = capturado.execucoes[0] as ExecucaoObservacao & Record<string, unknown>;
    expect(execucao.actorUserProfileId).toBe(USER);
    expect(execucao.organizationId).toBe(ORG);
    expect(execucao.operationId).toBe(OPERACAO);
    for (const proibido of [
      "payload_hash",
      "payloadHash",
      "data",
      "instante",
      "status",
      "excluida",
      "domainState",
      "authorCollaboratorId",
      "membershipId",
    ]) {
      expect(Object.keys(execucao), proibido).not.toContain(proibido);
    }
  });
});

describe("F5-11 P4 — erros da RPC: três caminhos, fail-closed", () => {
  it("R: caminho 1 (erro de execução) traduz SÓ os prefixos `F5_11_*` e não vaza a mensagem crua", async () => {
    const casos: readonly (readonly [string, number, CodigoPublico])[] = [
      ["F5_11_FORBIDDEN: ator sem capability", 403, "FORBIDDEN"],
      ["F5_11_NOT_FOUND: observacao inexistente", 404, "NOT_FOUND"],
      ["F5_11_CONFLICT: versao divergente", 409, "CONFLICT"],
      ["F5_11_INVALID_INPUT: texto obrigatorio", 400, "INVALID_INPUT"],
      ["duplicate key value violates unique constraint", 500, "INTERNAL"],
      ["F5_10_CONFLICT: outro dominio", 500, "INTERNAL"],
      ["F5_09_FORBIDDEN: outro dominio", 500, "INTERNAL"],
    ];
    for (const [mensagem, status, codigo] of casos) {
      const { resposta } = await executar(corpo("observacao.editar"), {
        rpc: { error: { code: "P0001", message: mensagem } },
      });
      expect(resposta.status, mensagem).toBe(status);
      const texto = await resposta.text();
      const devolvido = JSON.parse(texto) as CorpoErro;
      expect(devolvido.error?.code, mensagem).toBe(codigo);
      expect(texto, mensagem).not.toContain("duplicate key");
      expect(texto, mensagem).not.toContain("P0001");
      expect(texto, mensagem).not.toContain("F5_11_");
    }
  });

  it("S: caminho 2 (corpo 2xx com `error`) usa a MESMA tradução fail-closed", async () => {
    const conflito = await executar(corpo("observacao.editar"), {
      rpc: { data: { error: { code: "P0001", message: "F5_11_CONFLICT: versao divergente" } } },
    });
    expect(conflito.resposta.status).toBe(409);
    expect(((await conflito.resposta.json()) as CorpoErro).error?.code).toBe("CONFLICT");

    const desconhecido = await executar(corpo("observacao.editar"), {
      rpc: { data: { error: { message: "falha inesperada do banco" } } },
    });
    expect(desconhecido.resposta.status).toBe(500);
    expect(((await desconhecido.resposta.json()) as CorpoErro).error?.code).toBe("INTERNAL");
  });

  it("T: caminho 3 (corpo 2xx declarando `ok` diferente de `true`) nunca é sucesso", async () => {
    for (const valor of [false, 0, "sim", null]) {
      const { resposta } = await executar(corpo("observacao.obter"), {
        rpc: { data: { ok: valor } },
      });
      expect(resposta.status, String(valor)).toBe(500);
      const devolvido = (await resposta.json()) as CorpoErro;
      expect(devolvido.error?.code, String(valor)).toBe("INTERNAL");
      expect(devolvido.error?.message, String(valor)).toBe("Resposta inesperada do servidor.");
    }

    // Payload soberano SEM a chave `ok` é sucesso normal (a ausência não é
    // inconsistência — quem exige `ok === true` é o adapter de cliente).
    const semOk = await executar(corpo("observacao.obter"), { rpc: { data: { id: OBSERVACAO } } });
    expect(semOk.resposta.status).toBe(200);
    expect(((await semOk.resposta.json()) as CorpoSucesso).ok).toBe(true);
  });

  it("U: `codigoDeErroRpc` é exaustivo no vocabulário do domínio", () => {
    expect(codigoDeErroRpc({ message: "F5_11_FORBIDDEN: x" })).toBe("FORBIDDEN");
    expect(codigoDeErroRpc({ message: "F5_11_NOT_FOUND: x" })).toBe("NOT_FOUND");
    expect(codigoDeErroRpc({ message: "F5_11_CONFLICT: x" })).toBe("CONFLICT");
    expect(codigoDeErroRpc({ message: "F5_11_INVALID_INPUT: x" })).toBe("INVALID_INPUT");
    expect(codigoDeErroRpc({})).toBe("INTERNAL");
    expect(codigoDeErroRpc({ message: "F5_11_DESCONHECIDO: x" })).toBe("INTERNAL");
    expect(codigoDeErroRpc({ message: "F5_10_CONFLICT: x" })).toBe("INTERNAL");
    expect(codigoDeErroRpc({ message: "P0001" })).toBe("INTERNAL");
  });
});
