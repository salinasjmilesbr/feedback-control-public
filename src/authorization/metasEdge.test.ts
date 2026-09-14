import { describe, expect, it } from "vitest";
import {
  codigoDeErroRpc,
  metas,
  type AlvoFuncionalMeta,
  type DepsMetas,
  type ExecucaoMeta,
  type ResultadoRpcMeta,
} from "../../supabase/functions/metas/core.ts";
import type { AuthIdentity } from "../auth/tipos.ts";
import type { CodigoPublico } from "../infrastructure/supabase/metas/contrato.ts";

/**
 * F5-10 P5 (Issue #218) — fronteira soberana de METAS na Edge.
 *
 * Prova, com o núcleo REAL da Edge (`metas(req, deps)`, não mockado) e
 * dependências sintéticas, a ordem normativa e o fail-closed:
 * método → JWT (`auth.getUser`) → forma → tenant revalidado → gate → RPC
 * privilegiada. A RPC NUNCA é chamada antes da decisão; o ator é SEMPRE o
 * `auth.uid` verificado (nunca do corpo); erro da RPC só vira código público
 * pelos prefixos `F5_10_*`; mensagem crua do banco não vaza.
 *
 * Nenhum dado real: todos os identificadores são UUID sintéticos.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const USER = "33333333-3333-4333-8333-333333333333";
const CICLO = "55555555-5555-4555-8555-555555555555";
const OPERACAO = "66666666-6666-4666-8666-666666666666";
const COLABORADOR = "77777777-7777-4777-8777-777777777777";
const GOAL = "88888888-8888-4888-8888-888888888888";
const URL_EDGE = "https://edge.local/functions/v1/metas";

interface CorpoErro {
  readonly error?: { readonly code?: string; readonly message?: string };
}
interface CorpoSucesso {
  readonly ok?: boolean;
  readonly operacao?: string;
  readonly resultado?: unknown;
}

function identidade(overrides: Partial<AuthIdentity> = {}): AuthIdentity {
  return {
    authUserId: USER,
    perfil: { id: USER, status: "active" },
    memberships: [{ id: "m-1", organizationId: ORG, status: "active" }],
    organizacoes: [{ id: ORG, name: "Organizacao sintetica" }],
    ...overrides,
  } as unknown as AuthIdentity;
}

/** Corpo VÁLIDO de `goal.criar` (base das provas de forma). */
function corpoCriar(): Record<string, unknown> {
  return {
    organization_id: ORG,
    operacao: "goal.criar",
    operation_id: OPERACAO,
    cycle_id: CICLO,
    collaborator_id: COLABORADOR,
    tipo: "INDIVIDUAL",
    descricao: "Meta sintetica",
    kpi: "Indicador sintetico",
    valor_alvo: "100",
  };
}

/** Corpo VÁLIDO de `goal.editar` (mutação de meta existente). */
function corpoEditar(organizationId: string = ORG): Record<string, unknown> {
  return {
    organization_id: organizationId,
    operacao: "goal.editar",
    operation_id: OPERACAO,
    goal_id: GOAL,
    descricao: "Meta sintetica editada",
    kpi: "Indicador sintetico",
    valor_alvo: "120",
    expected_version: 3,
  };
}

interface Cenario {
  readonly identidade?: AuthIdentity | null;
  readonly capabilities?: readonly string[];
  readonly autorizacao?: { readonly permitido: boolean; readonly code?: CodigoPublico };
  readonly rpc?: ResultadoRpcMeta;
}

interface Capturado {
  readonly alvos: AlvoFuncionalMeta[];
  readonly capabilities: { readonly actorUserProfileId: string; readonly organizationId: string }[];
  readonly execucoes: ExecucaoMeta[];
}

function cenarioBase(): Capturado {
  return { alvos: [], capabilities: [], execucoes: [] };
}

function deps(entrada: Cenario, capturado: Capturado): DepsMetas {
  return {
    resolveCaller: async (authHeader) => (authHeader === "Bearer ok" ? USER : null),
    resolverIdentidade: async () =>
      entrada.identidade === undefined ? identidade() : entrada.identidade,
    resolverCapabilitiesEfetivas: async (pedido) => {
      capturado.capabilities.push(pedido);
      return (entrada.capabilities ?? []).map((capability_code) => ({ capability_code }));
    },
    avaliarAutorizacao: async ({ alvo }) => {
      capturado.alvos.push(alvo);
      return entrada.autorizacao ?? { permitido: true };
    },
    executarRpc: async (execucao) => {
      capturado.execucoes.push(execucao);
      return entrada.rpc ?? { data: { goal_id: GOAL, version: 1, status: "EM_ANDAMENTO" } };
    },
  };
}

function pedido(
  corpo: unknown,
  opcoes: { readonly method?: string; readonly auth?: string | null } = {}
): Request {
  const method = opcoes.method ?? "POST";
  const headers = new Headers();
  if (opcoes.auth !== null) headers.set("Authorization", opcoes.auth ?? "Bearer ok");
  const semCorpo = opcoes.method !== undefined && method !== "POST";
  return semCorpo
    ? new Request(URL_EDGE, { method, headers })
    : new Request(URL_EDGE, { method, headers, body: JSON.stringify(corpo) });
}

async function executar(
  corpo: unknown,
  entrada: Cenario = {},
  opcoes: { readonly method?: string; readonly auth?: string | null } = {}
): Promise<{ resposta: Response; capturado: Capturado }> {
  const capturado = cenarioBase();
  const resposta = await metas(pedido(corpo, opcoes), deps(entrada, capturado));
  return { resposta, capturado };
}

describe("F5-10 P5 — ordem normativa da fronteira de metas", () => {
  it("A: OPTIONS responde 200 com CORS, sem exigir credencial", async () => {
    const { resposta, capturado } = await executar(null, {}, { method: "OPTIONS", auth: null });
    expect(resposta.status).toBe(200);
    expect(await resposta.text()).toBe("ok");
    expect(resposta.headers.get("Access-Control-Allow-Origin")).toBe("*");
    expect(capturado.execucoes).toHaveLength(0);
  });

  it("B: método não-POST é 405 METHOD_NOT_ALLOWED e não toca a RPC", async () => {
    for (const method of ["PUT", "DELETE", "PATCH"]) {
      const { resposta, capturado } = await executar(corpoCriar(), {}, { method });
      expect(resposta.status, method).toBe(405);
      const corpo = (await resposta.json()) as CorpoErro;
      expect(corpo.error?.code, method).toBe("METHOD_NOT_ALLOWED");
      expect(capturado.execucoes, method).toHaveLength(0);
    }
  });

  it("C: POST sem header Authorization é 401 NOT_AUTHORIZED", async () => {
    const { resposta, capturado } = await executar(corpoCriar(), {}, { auth: null });
    expect(resposta.status).toBe(401);
    expect(((await resposta.json()) as CorpoErro).error?.code).toBe("NOT_AUTHORIZED");
    expect(capturado.execucoes).toHaveLength(0);
  });

  it("D: JWT que não resolve identidade soberana é 401 (nada é executado)", async () => {
    const { resposta, capturado } = await executar(corpoCriar(), {}, { auth: "Bearer invalido" });
    expect(resposta.status).toBe(401);
    expect(((await resposta.json()) as CorpoErro).error?.code).toBe("NOT_AUTHORIZED");
    expect(capturado.alvos).toHaveLength(0);
    expect(capturado.execucoes).toHaveLength(0);
  });

  it("E: corpo que não é JSON é 400 INVALID_INPUT", async () => {
    const capturado = cenarioBase();
    const resposta = await metas(
      new Request(URL_EDGE, {
        method: "POST",
        headers: { Authorization: "Bearer ok" },
        body: "{nao-e-json",
      }),
      deps({}, capturado)
    );
    expect(resposta.status).toBe(400);
    expect(((await resposta.json()) as CorpoErro).error?.code).toBe("INVALID_INPUT");
    expect(capturado.execucoes).toHaveLength(0);
  });
});

describe("F5-10 P5 — forma é FORMA, nunca autoridade", () => {
  it("F: operação desconhecida é 400 (sem default permissivo)", async () => {
    for (const operacao of [
      "goal.invalidar_aprovacoes",
      "goal.listar",
      "meta.criar",
      "cycle.editar",
      "",
    ]) {
      const { resposta, capturado } = await executar({ ...corpoCriar(), operacao });
      expect(resposta.status, operacao).toBe(400);
      expect(((await resposta.json()) as CorpoErro).error?.code, operacao).toBe("INVALID_INPUT");
      expect(capturado.execucoes, operacao).toHaveLength(0);
    }
  });

  it("G: campos de identidade/autoridade no corpo são 400 e a RPC não roda", async () => {
    const proibidos: readonly (readonly [string, unknown])[] = [
      ["status", "ATIVO"],
      ["aprovado", true],
      ["domainState", { metaExistente: true }],
      ["excluida", false],
      ["version", 1],
      ["payload_hash", "0".repeat(64)],
      ["actor_id", COLABORADOR],
      ["actor_user_profile_id", COLABORADOR],
      ["membership_id", "m-1"],
      ["capability", "goal.write"],
      ["role", "admin"],
      ["cargo", "Diretor"],
      ["funcao", "GERENTE"],
    ];
    for (const [campo, valor] of proibidos) {
      const { resposta, capturado } = await executar({ ...corpoCriar(), [campo]: valor });
      expect(resposta.status, campo).toBe(400);
      expect(((await resposta.json()) as CorpoErro).error?.code, campo).toBe("INVALID_INPUT");
      expect(capturado.execucoes, campo).toHaveLength(0);
    }
  });

  it("H: campo de OUTRA operação é recusado (allowlist por operação)", async () => {
    for (const extra of [
      { goal_id: GOAL },
      { expected_version: 3 },
      { resultado_final: "concluida" },
      { papel: "GERENTE" },
    ]) {
      const { resposta } = await executar({ ...corpoCriar(), ...extra });
      expect(resposta.status, JSON.stringify(extra)).toBe(400);
    }
  });
});

describe("F5-10 P5 — tenant revalidado ANTES do gate", () => {
  it("I: organização sem membership ativa é 403 sem consultar o gate nem a RPC", async () => {
    const { resposta, capturado } = await executar(corpoEditar(ORG_B));
    expect(resposta.status).toBe(403);
    expect(((await resposta.json()) as CorpoErro).error?.code).toBe("FORBIDDEN");
    expect(capturado.alvos).toHaveLength(0);
    expect(capturado.execucoes).toHaveLength(0);
  });

  it("J: identidade ausente é 401 e perfil inativo é 403 (sem tocar a RPC)", async () => {
    const semIdentidade = await executar(corpoCriar(), { identidade: null });
    expect(semIdentidade.resposta.status).toBe(401);

    const inativo = await executar(corpoCriar(), {
      identidade: identidade({
        perfil: { id: USER, status: "disabled" },
        memberships: [],
      }),
    });
    expect(inativo.resposta.status).toBe(403);
    expect(((await inativo.resposta.json()) as CorpoErro).error?.code).toBe("FORBIDDEN");
    expect(inativo.capturado.execucoes).toHaveLength(0);
  });

  it("K: membership ativa em OUTRA organização não autoriza o tenant do corpo", async () => {
    const { resposta } = await executar(corpoCriar(), {
      identidade: identidade({
        memberships: [{ id: "m-2", organizationId: ORG_B, status: "active" }],
        organizacoes: [{ id: ORG_B, name: "Outra organizacao" }],
      }),
    });
    expect(resposta.status).toBe(403);
  });

  it("L: membership INATIVA na organização do corpo é 403", async () => {
    const { resposta } = await executar(corpoCriar(), {
      identidade: identidade({
        memberships: [{ id: "m-1", organizationId: ORG, status: "disabled" }],
        organizacoes: [],
      }),
    });
    expect(resposta.status).toBe(403);
  });
});

describe("F5-10 P5 — gate por operação (alvo REAL, sem default)", () => {
  it("M: `goal.criar` avalia `goal.write` sobre o COLABORADOR dono", async () => {
    const { resposta, capturado } = await executar(corpoCriar());
    expect(resposta.status).toBe(200);
    expect(capturado.alvos).toEqual([{ type: "collaborator", id: COLABORADOR }]);
    expect(capturado.capabilities).toHaveLength(0);
  });

  it("N: mutações de meta avaliam `goal.write` sobre a META real (nunca alvo sintético)", async () => {
    const { resposta, capturado } = await executar(corpoEditar());
    expect(resposta.status).toBe(200);
    expect(capturado.alvos).toEqual([{ type: "goal", id: GOAL }]);
  });

  it("O: `goal.aprovar` usa `goal.approve` e `goal.definir_limites_do_ciclo` usa `cycle.manage` sobre o CICLO", async () => {
    const aprovar = await executar({
      organization_id: ORG,
      operacao: "goal.aprovar",
      operation_id: OPERACAO,
      goal_id: GOAL,
      papel: "GERENTE",
      expected_version: 2,
    });
    expect(aprovar.resposta.status).toBe(200);
    expect(aprovar.capturado.alvos).toEqual([{ type: "goal", id: GOAL }]);

    const limites = await executar({
      organization_id: ORG,
      operacao: "goal.definir_limites_do_ciclo",
      operation_id: OPERACAO,
      cycle_id: CICLO,
      tipo: "NEGOCIO_PROJETO",
      quantidade: 2,
      motivo: "Ajuste de quota sintetico",
      expected_version: 1,
    });
    expect(limites.resposta.status).toBe(200);
    expect(limites.capturado.alvos).toEqual([{ type: "cycle", id: CICLO }]);
    expect(limites.capturado.execucoes[0]?.cycleId).toBe(CICLO);
    expect(limites.capturado.execucoes[0]?.quantidade).toBe(2);
  });

  it("P: negação do gate vira o código público e a RPC NÃO é chamada", async () => {
    const negado = await executar(corpoEditar(), {
      autorizacao: { permitido: false, code: "CONFLICT" },
    });
    expect(negado.resposta.status).toBe(409);
    expect(((await negado.resposta.json()) as CorpoErro).error?.code).toBe("CONFLICT");
    expect(negado.capturado.execucoes).toHaveLength(0);

    const semCodigo = await executar(corpoEditar(), { autorizacao: { permitido: false } });
    expect(semCodigo.resposta.status).toBe(403);
    expect(((await semCodigo.resposta.json()) as CorpoErro).error?.code).toBe("FORBIDDEN");
    expect(semCodigo.capturado.execucoes).toHaveLength(0);
  });

  it("Q: `goal.listar_por_escopo` é ADMINISTRATIVO — capability efetiva, sem alvo no engine", async () => {
    const corpo = {
      organization_id: ORG,
      operacao: "goal.listar_por_escopo",
      operation_id: OPERACAO,
      cycle_id: CICLO,
    };

    const semCapability = await executar(corpo, { capabilities: ["goal.write"] });
    expect(semCapability.resposta.status).toBe(403);
    expect(semCapability.capturado.alvos).toHaveLength(0);
    expect(semCapability.capturado.capabilities).toEqual([
      { actorUserProfileId: USER, organizationId: ORG },
    ]);

    const comCapability = await executar(corpo, { capabilities: ["goal.read"] });
    expect(comCapability.resposta.status).toBe(200);
    expect(comCapability.capturado.alvos).toHaveLength(0);
    expect(comCapability.capturado.execucoes[0]?.goalId).toBeNull();
    expect(comCapability.capturado.execucoes[0]?.cycleId).toBe(CICLO);
  });
});

describe("F5-10 P5 — execução privilegiada pós-decisão e erros públicos", () => {
  it("R: sucesso devolve `{ok, operacao, resultado}` e o ATOR VERIFICADO (nunca do corpo)", async () => {
    const { resposta, capturado } = await executar(corpoCriar());
    expect(resposta.status).toBe(200);
    const corpo = (await resposta.json()) as CorpoSucesso;
    expect(corpo.ok).toBe(true);
    expect(corpo.operacao).toBe("goal.criar");
    expect(corpo.resultado).toEqual({ goal_id: GOAL, version: 1, status: "EM_ANDAMENTO" });

    const execucao = capturado.execucoes[0];
    expect(execucao?.actorUserProfileId).toBe(USER);
    expect(execucao?.organizationId).toBe(ORG);
    expect(execucao?.collaboratorId).toBe(COLABORADOR);
    expect(execucao?.cycleId).toBe(CICLO);
    expect(execucao?.operationId).toBe(OPERACAO);
    expect(execucao?.tipo).toBe("INDIVIDUAL");
  });

  it("S: erro da RPC é traduzido só pelos prefixos `F5_10_*` e nunca vaza a mensagem crua", async () => {
    const casos: readonly (readonly [string, number, CodigoPublico])[] = [
      ["F5_10_FORBIDDEN: ator sem capability", 403, "FORBIDDEN"],
      ["F5_10_NOT_FOUND: meta inexistente", 404, "NOT_FOUND"],
      ["F5_10_CONFLICT: versao divergente", 409, "CONFLICT"],
      ["F5_10_INVALID_INPUT: descricao obrigatoria", 400, "INVALID_INPUT"],
      ["F5_10_INTERNAL: falha interna", 500, "INTERNAL"],
      ["duplicate key value violates unique constraint", 500, "INTERNAL"],
    ];
    for (const [mensagem, status, codigo] of casos) {
      const { resposta } = await executar(corpoCriar(), {
        rpc: { error: { code: "P0001", message: mensagem } },
      });
      expect(resposta.status, mensagem).toBe(status);
      const texto = await resposta.text();
      const corpo = JSON.parse(texto) as CorpoErro;
      expect(corpo.error?.code, mensagem).toBe(codigo);
      expect(texto, mensagem).not.toContain("duplicate key");
      expect(texto, mensagem).not.toContain("P0001");
    }
  });

  it("T: `codigoDeErroRpc` é exaustivo no vocabulário público", () => {
    expect(codigoDeErroRpc({ message: "F5_10_FORBIDDEN: x" })).toBe("FORBIDDEN");
    expect(codigoDeErroRpc({ message: "F5_10_NOT_FOUND: x" })).toBe("NOT_FOUND");
    expect(codigoDeErroRpc({ message: "F5_10_CONFLICT: x" })).toBe("CONFLICT");
    expect(codigoDeErroRpc({ message: "F5_10_INVALID_INPUT: x" })).toBe("INVALID_INPUT");
    expect(codigoDeErroRpc({ message: "F5_10_NOT_AUTHORIZED: x" })).toBe("NOT_AUTHORIZED");
    expect(codigoDeErroRpc({ message: "F5_10_INTERNAL: x" })).toBe("INTERNAL");
    expect(codigoDeErroRpc({})).toBe("INTERNAL");
    expect(codigoDeErroRpc({ message: "F5_09_CONFLICT: outro dominio" })).toBe("INTERNAL");
  });

  it("U: a RPC recebe a intenção idempotente e os campos da operação (sem payload hash)", async () => {
    const { capturado } = await executar(corpoCriar());
    const execucao = capturado.execucoes[0] as ExecucaoMeta & Record<string, unknown>;
    expect(execucao.operationId).toBe(OPERACAO);
    expect(Object.keys(execucao)).not.toContain("payloadHash");
    expect(Object.keys(execucao)).not.toContain("payload_hash");
    // Nada de estado/versão inventado na fronteira para a criação.
    expect(execucao.expectedVersion).toBeNull();
    expect(execucao.goalId).toBeNull();
  });

  it("V: a mesma intenção com o mesmo `operation_id` produz a mesma execução (idempotência é da RPC)", async () => {
    const primeira = await executar(corpoEditar());
    const segunda = await executar(corpoEditar());
    expect(primeira.capturado.execucoes).toEqual(segunda.capturado.execucoes);
    expect(primeira.resposta.status).toBe(200);
    expect(segunda.resposta.status).toBe(200);
  });
});
