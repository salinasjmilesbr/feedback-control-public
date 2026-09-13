import { describe, expect, it } from "vitest";
import {
  ciclos,
  codigoDeErroRpc,
  type DepsCiclos,
  type ExecucaoCiclo,
  type ResultadoRpcCiclo,
} from "../../supabase/functions/ciclos/core.ts";
import type { AuthIdentity } from "../auth/tipos.ts";
import type { CodigoPublico } from "../infrastructure/supabase/ciclos/contrato.ts";

/**
 * F5-09 P7 (Issue #202) — fronteira soberana de CICLOS na Edge.
 *
 * Prova, com o núcleo REAL da Edge (não mockado) e dependências soberanas
 * sintéticas, a cobertura obrigatória A–R: happy path por operação, UUID real
 * como alvo, cross-tenant/IDOR, membership/perfil/identidade, capability e
 * scope, cargo/função/papel textual, `organizationId`/`actorId`/`status` do
 * corpo sem autoridade, alvo malformado/sintético, `service_role` só depois da
 * autorização, ausência de matriz de lifecycle na Edge e idempotência
 * (`operationId`) preservada por repasse.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const USER = "33333333-3333-4333-8333-333333333333";
const CICLO = "55555555-5555-4555-8555-555555555555";
const OPERACAO = "66666666-6666-4666-8666-666666666666";
const COLABORADOR = "77777777-7777-4777-8777-777777777777";

function identidade(overrides: Partial<AuthIdentity> = {}): AuthIdentity {
  return {
    authUserId: USER,
    perfil: { id: USER, status: "active" },
    memberships: [{ id: "m-1", organizationId: ORG, status: "active" }],
    organizacoes: [{ id: ORG, name: "Org sintetica" }],
    ...overrides,
  } as unknown as AuthIdentity;
}

interface Cenario {
  readonly identidade?: AuthIdentity | null;
  readonly capabilities?: readonly string[];
  readonly autorizacao?: { readonly permitido: boolean; readonly code?: CodigoPublico };
  readonly rpc?: ResultadoRpcCiclo;
  readonly semMatricula?: boolean;
  readonly matriculaResolvida?: string | null;
}

interface Capturado {
  readonly alvos: { readonly type: "cycle"; readonly id: string }[];
  readonly execucoes: ExecucaoCiclo[];
}

function deps(cenario: Cenario, capturado: Capturado): DepsCiclos {
  return {
    resolveCaller: async (authHeader) =>
      authHeader === "Bearer ok" ? USER : null,
    resolverIdentidade: async () =>
      cenario.identidade === undefined ? identidade() : cenario.identidade,
    resolverCapabilitiesEfetivas: async () =>
      (cenario.capabilities ?? []).map((capability_code) => ({ capability_code })),
    avaliarAutorizacao: async ({ alvo }) => {
      capturado.alvos.push(alvo);
      return cenario.autorizacao ?? { permitido: true };
    },
    ...(cenario.semMatricula
      ? {}
      : {
          resolverMatricula: async () =>
            cenario.matriculaResolvida === undefined ? COLABORADOR : cenario.matriculaResolvida,
        }),
    executarRpc: async (execucao) => {
      capturado.execucoes.push(execucao);
      return cenario.rpc ?? { data: { version: 1 }, error: null };
    },
  };
}

function requisicao(corpo: unknown, comAutorizacao = true): Request {
  return new Request("http://localhost/functions/v1/ciclos", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(comAutorizacao ? { Authorization: "Bearer ok" } : {}),
    },
    body: JSON.stringify(corpo),
  });
}

async function chamar(
  corpo: unknown,
  cenario: Cenario = {},
  comAutorizacao = true
): Promise<{
  readonly resposta: Response;
  readonly json: { ok?: boolean; error?: { code?: string; message?: string }; resultado?: unknown };
  readonly capturado: Capturado;
}> {
  const capturado: Capturado = { alvos: [], execucoes: [] };
  const resposta = await ciclos(requisicao(corpo, comAutorizacao), deps(cenario, capturado));
  const json = (await resposta.json()) as {
    ok?: boolean;
    error?: { code?: string; message?: string };
    resultado?: unknown;
  };
  return { resposta, json, capturado };
}

const CORPO_EDITAR = {
  organization_id: ORG,
  operacao: "cycle.editar",
  cycle_id: CICLO,
  operation_id: OPERACAO,
  expected_version: 3,
  ano: 2035,
  numero: 1,
  data_inicio: "2035-01-01",
  data_fim: "2035-03-31",
};

describe("F5-09 P7 — Edge `ciclos`: forma, método e autenticação", () => {
  it("OPTIONS responde 200; método diferente de POST é 405", async () => {
    const capturado: Capturado = { alvos: [], execucoes: [] };
    const opcoes = await ciclos(
      new Request("http://localhost/functions/v1/ciclos", { method: "OPTIONS" }),
      deps({}, capturado)
    );
    expect(opcoes.status).toBe(200);

    const get = await ciclos(
      new Request("http://localhost/functions/v1/ciclos", { method: "GET" }),
      deps({}, capturado)
    );
    expect(get.status).toBe(405);
    expect(((await get.json()) as { error: { code: string } }).error.code).toBe(
      "METHOD_NOT_ALLOWED"
    );
  });

  it("sem Authorization é 401 e sem tocar RPC", async () => {
    const { resposta, capturado } = await chamar(CORPO_EDITAR, {}, false);
    expect(resposta.status).toBe(401);
    expect(capturado.execucoes).toEqual([]);
  });

  it("caller inválido (JWT não verificável) é 401", async () => {
    const capturado: Capturado = { alvos: [], execucoes: [] };
    const resposta = await ciclos(
      new Request("http://localhost/functions/v1/ciclos", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: "Bearer ruim" },
        body: JSON.stringify(CORPO_EDITAR),
      }),
      deps({}, capturado)
    );
    expect(resposta.status).toBe(401);
    expect(capturado.execucoes).toEqual([]);
  });

  it("operação desconhecida e corpo inválido são INVALID_INPUT (400)", async () => {
    const desconhecida = await chamar({ ...CORPO_EDITAR, operacao: "cycle.excluir" });
    expect(desconhecida.resposta.status).toBe(400);

    const vazio = await chamar({});
    expect(vazio.resposta.status).toBe(400);

    const capturado: Capturado = { alvos: [], execucoes: [] };
    const semJson = await ciclos(
      new Request("http://localhost/functions/v1/ciclos", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: "Bearer ok" },
        body: "{",
      }),
      deps({}, capturado)
    );
    expect(semJson.status).toBe(400);
    expect(capturado.execucoes).toEqual([]);
  });
});

describe("F5-09 P7 — happy path por operação (A) e UUID real (B)", () => {
  const casos = [
    {
      operacao: "cycle.criar",
      corpo: {
        organization_id: ORG,
        operacao: "cycle.criar",
        operation_id: OPERACAO,
        ano: 2035,
        numero: 2,
        data_inicio: "2035-04-01",
        data_fim: "2035-06-30",
      },
      capabilities: ["cycle.manage"],
      alvos: 0,
    },
    { operacao: "cycle.editar", corpo: CORPO_EDITAR, capabilities: [], alvos: 1 },
    {
      operacao: "cycle.ativar",
      corpo: {
        organization_id: ORG,
        operacao: "cycle.ativar",
        cycle_id: CICLO,
        operation_id: OPERACAO,
        expected_version: 3,
      },
      capabilities: [],
      alvos: 1,
    },
    {
      operacao: "cycle.encerrar",
      corpo: {
        organization_id: ORG,
        operacao: "cycle.encerrar",
        cycle_id: CICLO,
        operation_id: OPERACAO,
        expected_version: 3,
        motivo: "Fim do periodo",
      },
      capabilities: [],
      alvos: 1,
    },
    {
      operacao: "cycle.cancelar",
      corpo: {
        organization_id: ORG,
        operacao: "cycle.cancelar",
        cycle_id: CICLO,
        operation_id: OPERACAO,
        expected_version: 3,
        motivo: "Interrupcao",
      },
      capabilities: [],
      alvos: 1,
    },
    {
      operacao: "cycle.reabrir",
      corpo: {
        organization_id: ORG,
        operacao: "cycle.reabrir",
        cycle_id: CICLO,
        operation_id: OPERACAO,
        expected_version: 3,
        motivo: "Erro de encerramento",
      },
      capabilities: [],
      alvos: 1,
    },
    {
      operacao: "cycle.corrigir_periodo",
      corpo: {
        organization_id: ORG,
        operacao: "cycle.corrigir_periodo",
        cycle_id: CICLO,
        operation_id: OPERACAO,
        expected_version: 3,
        data_inicio: "2035-01-02",
        data_fim: "2035-03-30",
        justificativa: "Ajuste contratual",
      },
      capabilities: [],
      alvos: 1,
    },
    {
      operacao: "cycle.admissao.incluir",
      corpo: {
        organization_id: ORG,
        operacao: "cycle.admissao.incluir",
        cycle_id: CICLO,
        operation_id: OPERACAO,
        expected_version: 3,
        motivo: "Admitido apos a ativacao",
        matricula: "MAT-9",
      },
      capabilities: [],
      alvos: 1,
    },
  ] as const;

  it.each(casos.map((caso) => [caso.operacao, caso] as const))(
    "%s: autoriza, executa UMA vez com o ator verificado e devolve o resultado",
    async (_operacao, caso) => {
      const { resposta, json, capturado } = await chamar(caso.corpo, {
        capabilities: caso.capabilities,
        rpc: { data: { version: 4 }, error: null },
      });

      expect(resposta.status).toBe(200);
      expect(json.ok).toBe(true);
      expect(json.resultado).toEqual({ version: 4 });
      expect(capturado.execucoes).toHaveLength(1);

      const execucao = capturado.execucoes[0]!;
      // O ator é SEMPRE o `auth.uid` verificado — nunca o corpo.
      expect(execucao.actorUserProfileId).toBe(USER);
      expect(execucao.organizationId).toBe(ORG);
      expect(execucao.operationId).toBe(OPERACAO);
      // Admissão: o UUID resolvido da intenção segue para a RPC.
      if (caso.operacao === "cycle.admissao.incluir") {
        expect(execucao.collaboratorId).toBe(COLABORADOR);
      }
      // Alvo REAL (UUID canônico) nas operações funcionais; criação é
      // administrativa (nenhum alvo sintético é inventado).
      expect(capturado.alvos).toHaveLength(caso.alvos);
      if (caso.alvos === 1) {
        expect(capturado.alvos[0]).toEqual({ type: "cycle", id: CICLO });
      }
    }
  );

  it("cycle.criar exige a capability efetiva (plano administrativo D19/D21)", async () => {
    const semCapability = await chamar(
      {
        organization_id: ORG,
        operacao: "cycle.criar",
        operation_id: OPERACAO,
        ano: 2035,
        numero: 2,
        data_inicio: "2035-04-01",
        data_fim: "2035-06-30",
      },
      { capabilities: [] }
    );
    expect(semCapability.resposta.status).toBe(403);
    expect(semCapability.capturado.execucoes).toEqual([]);
  });
});

describe("F5-09 P7 — tenant, membership, perfil e identidade (C/D/E/I)", () => {
  it("organization_id do corpo NÃO define tenant: divergência é negada", async () => {
    const { resposta, capturado } = await chamar(
      { ...CORPO_EDITAR, organization_id: ORG_B },
      { capabilities: ["cycle.manage"] }
    );
    expect(resposta.status).toBe(403);
    expect(capturado.execucoes).toEqual([]);
    expect(capturado.alvos).toEqual([]);
  });

  it("membership revogada/ausente ⇒ DENY sem tocar RPC", async () => {
    const { resposta, capturado } = await chamar(CORPO_EDITAR, {
      identidade: identidade({ memberships: [] }),
    });
    expect(resposta.status).toBe(403);
    expect(capturado.execucoes).toEqual([]);
  });

  it("perfil inativo ⇒ DENY", async () => {
    const { resposta } = await chamar(CORPO_EDITAR, {
      identidade: identidade({ perfil: { id: USER, status: "disabled" } } as never),
    });
    expect(resposta.status).toBe(403);
  });

  it("identidade inexistente ⇒ 401", async () => {
    const { resposta, capturado } = await chamar(CORPO_EDITAR, { identidade: null });
    expect(resposta.status).toBe(401);
    expect(capturado.execucoes).toEqual([]);
  });

  it("cross-tenant/IDOR: negação do Policy Engine vira erro público e nada é executado", async () => {
    const negado = await chamar(CORPO_EDITAR, {
      autorizacao: { permitido: false, code: "NOT_FOUND" },
    });
    expect(negado.resposta.status).toBe(404);
    expect(negado.capturado.execucoes).toEqual([]);

    const proibido = await chamar(CORPO_EDITAR, {
      autorizacao: { permitido: false, code: "FORBIDDEN" },
    });
    expect(proibido.resposta.status).toBe(403);
    expect(proibido.capturado.execucoes).toEqual([]);
  });
});

describe("F5-09 P7 — alvo, payload e autoridade textual (F/G/H/J/K/L)", () => {
  it("cycle_id malformado, sintético ou ausente é recusado ANTES da autorização", async () => {
    for (const cycleId of ["", "global", "2035-1", `${CICLO}x`]) {
      const { resposta, capturado } = await chamar({ ...CORPO_EDITAR, cycle_id: cycleId });
      expect(resposta.status, cycleId).toBe(400);
      expect(capturado.alvos).toEqual([]);
      expect(capturado.execucoes).toEqual([]);
    }

    const semAlvo = await chamar({ ...CORPO_EDITAR, cycle_id: undefined });
    expect(semAlvo.resposta.status).toBe(400);
    expect(semAlvo.capturado.execucoes).toEqual([]);
  });

  it("operation_id e expected_version inválidos são recusados", async () => {
    const semOperacaoId = await chamar({ ...CORPO_EDITAR, operation_id: "nao-uuid" });
    expect(semOperacaoId.resposta.status).toBe(400);

    const semVersao = await chamar({ ...CORPO_EDITAR, expected_version: undefined });
    expect(semVersao.resposta.status).toBe(400);

    const versaoNegativa = await chamar({ ...CORPO_EDITAR, expected_version: -1 });
    expect(versaoNegativa.resposta.status).toBe(400);
  });

  it("actorId/authorId/cargo/funcao/papel/status no corpo NUNCA concedem autoridade", async () => {
    const campos = [
      { actorId: USER },
      { authorId: USER },
      { actor_user_profile_id: USER },
      { status: "ATIVO" },
      { capability: "cycle.manage" },
      { role: "admin" },
      { cargo: "Diretor" },
      { funcao: "GERENTE" },
      { papel: "admin" },
    ];

    for (const extra of campos) {
      const { resposta, capturado } = await chamar(
        { ...CORPO_EDITAR, ...extra },
        // Mesmo SEM capability/autorização no servidor, o campo textual do corpo
        // é recusado na forma: nada disso atravessa a fronteira.
        { autorizacao: { permitido: false, code: "FORBIDDEN" } }
      );
      expect(resposta.status, JSON.stringify(extra)).toBe(400);
      expect(capturado.alvos).toEqual([]);
      expect(capturado.execucoes).toEqual([]);
    }
  });

  it("status forjado no corpo não altera a decisão (o estado vem da linha soberana)", async () => {
    const { resposta, capturado } = await chamar(
      { ...CORPO_EDITAR, status: "PLANEJADO" },
      { autorizacao: { permitido: true } }
    );
    // `status` não é campo do contrato ⇒ recusa de forma, sem execução.
    expect(resposta.status).toBe(400);
    expect(capturado.execucoes).toEqual([]);
  });

  it("scope insuficiente e capability ausente/revogada ⇒ DENY (F/G)", async () => {
    const scope = await chamar(CORPO_EDITAR, {
      autorizacao: { permitido: false, code: "FORBIDDEN" },
    });
    expect(scope.resposta.status).toBe(403);
    expect(scope.capturado.execucoes).toEqual([]);

    const capabilityAusente = await chamar(
      {
        organization_id: ORG,
        operacao: "cycle.cancelar",
        cycle_id: CICLO,
        operation_id: OPERACAO,
        expected_version: 1,
        motivo: "Interrupcao",
      },
      { autorizacao: { permitido: false, code: "FORBIDDEN" } }
    );
    expect(capabilityAusente.resposta.status).toBe(403);
    expect(capabilityAusente.capturado.execucoes).toEqual([]);
  });

  it("admissão recusa campo estrutural e exige a resolução da intenção (§13.1 regra 9)", async () => {
    const estrutural = {
      organization_id: ORG,
      operacao: "cycle.admissao.incluir",
      cycle_id: CICLO,
      operation_id: OPERACAO,
      expected_version: 3,
      motivo: "Admitido apos a ativacao",
      collaborator_id: COLABORADOR,
      posicao_id: COLABORADOR,
      unidade_id: COLABORADOR,
      gestor_id: COLABORADOR,
      reporting_line_id: COLABORADOR,
      colegiado: [COLABORADOR],
      reference_date: "2035-02-01",
    };
    const recusado = await chamar(estrutural);
    expect(recusado.resposta.status).toBe(400);
    expect(recusado.capturado.execucoes).toEqual([]);

    // Sem UUID nem matrícula, ou com matrícula não resolvida ⇒ recusa.
    const semIntencao = await chamar({
      organization_id: ORG,
      operacao: "cycle.admissao.incluir",
      cycle_id: CICLO,
      operation_id: OPERACAO,
      expected_version: 3,
      motivo: "Admitido apos a ativacao",
    });
    expect(semIntencao.resposta.status).toBe(400);

    const naoResolvida = await chamar(
      {
        organization_id: ORG,
        operacao: "cycle.admissao.incluir",
        cycle_id: CICLO,
        operation_id: OPERACAO,
        expected_version: 3,
        motivo: "Admitido apos a ativacao",
        matricula: "MAT-9",
      },
      { matriculaResolvida: null }
    );
    expect(naoResolvida.resposta.status).toBe(400);
    expect(naoResolvida.capturado.execucoes).toEqual([]);

    // Intenção por MATRÍCULA: o UUID resolvido é o que chega ao executor.
    const porMatricula = await chamar({
      organization_id: ORG,
      operacao: "cycle.admissao.incluir",
      cycle_id: CICLO,
      operation_id: OPERACAO,
      expected_version: 3,
      motivo: "Admitido apos a ativacao",
      matricula: "MAT-9",
    });
    expect(porMatricula.resposta.status).toBe(200);
    expect(porMatricula.capturado.execucoes[0]!.collaboratorId).toBe(COLABORADOR);
  });
});

describe("F5-09 P7 — service_role como EXECUTOR (M) e sem matriz de lifecycle (N)", () => {
  it("erro da RPC é mapeado para código público, sem vazar mensagem interna", async () => {
    const conflito = await chamar(CORPO_EDITAR, {
      rpc: { data: null, error: { message: "F5_09_CONFLICT: versao divergente (expected_version desatualizado)" } },
    });
    expect(conflito.resposta.status).toBe(409);
    expect(conflito.json.error?.message).not.toContain("F5_09_CONFLICT");
    expect(conflito.json.error?.message).not.toContain("expected_version");

    const inexistente = await chamar(CORPO_EDITAR, {
      rpc: { data: null, error: { message: "F5_09_NOT_FOUND: ciclo inexistente ou de outro tenant" } },
    });
    expect(inexistente.resposta.status).toBe(404);

    const invalido = await chamar(CORPO_EDITAR, {
      rpc: { data: null, error: { message: "F5_09_INVALID_INPUT: ano deve estar entre 2000 e 2100" } },
    });
    expect(invalido.resposta.status).toBe(400);

    const inesperado = await chamar(CORPO_EDITAR, {
      rpc: { data: null, error: { message: "permission denied for function ciclo_editar" } },
    });
    expect(inesperado.resposta.status).toBe(500);
  });

  it("o mapeamento de erro da RPC é fail-closed para prefixos conhecidos", () => {
    expect(codigoDeErroRpc({ message: "F5_09_FORBIDDEN: x" })).toBe("FORBIDDEN");
    expect(codigoDeErroRpc({ message: "F5_09_NOT_FOUND: x" })).toBe("NOT_FOUND");
    expect(codigoDeErroRpc({ message: "F5_09_CONFLICT: x" })).toBe("CONFLICT");
    expect(codigoDeErroRpc({ message: "F5_09_INVALID_INPUT: x" })).toBe("INVALID_INPUT");
    expect(codigoDeErroRpc({ message: "F5_09_INTERNAL: x" })).toBe("INTERNAL");
    expect(codigoDeErroRpc({ message: "boom" })).toBe("INTERNAL");
    expect(codigoDeErroRpc({})).toBe("INTERNAL");
  });

  it("a Edge NÃO decide lifecycle: com o gate permitido, a RPC é sempre chamada", async () => {
    // O núcleo não inspeciona o status do ciclo — quem recusa estado é a RPC.
    const { resposta, capturado } = await chamar(CORPO_EDITAR, {
      autorizacao: { permitido: true },
      rpc: { data: null, error: { message: "F5_09_CONFLICT: edicao comum exige ciclo PLANEJADO" } },
    });
    expect(capturado.execucoes).toHaveLength(1);
    expect(resposta.status).toBe(409);
  });
});

describe("F5-09 P7 — idempotência por operationId (R/S)", () => {
  it("o MESMO operationId da intenção é repassado verbatim (a RPC é a dona da idempotência)", async () => {
    const primeira = await chamar(CORPO_EDITAR, { rpc: { data: { version: 4 } } });
    const segunda = await chamar(CORPO_EDITAR, { rpc: { data: { version: 4 } } });

    expect(primeira.capturado.execucoes[0]!.operationId).toBe(OPERACAO);
    expect(segunda.capturado.execucoes[0]!.operationId).toBe(OPERACAO);
  });

  it("mesmo operationId com intenção divergente é recusado pela RPC (CONFLICT)", async () => {
    const divergente = await chamar(
      { ...CORPO_EDITAR, ano: 2036 },
      { rpc: { data: null, error: { message: "F5_09_CONFLICT: operation_id ja utilizado com intencao diferente" } } }
    );
    expect(divergente.resposta.status).toBe(409);
    expect(divergente.capturado.execucoes[0]!.ano).toBe(2036);
  });
});
