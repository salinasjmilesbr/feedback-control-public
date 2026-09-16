import { describe, expect, it } from "vitest";

import type {
  ObservacaoSoberana,
  ObservationRepository,
  ResultadoObservacoes,
} from "../../application/ports/ObservationRepository";
import { criarControladorObservacoes } from "./controladorObservacoes";

/**
 * F5-11 P5 (Issue #250), L2 — o controlador gera idempotência, deriva
 * `expectedVersion` da LEITURA soberana, traduz negação em mensagem de UI e
 * NUNCA transporta autoridade (autoria/tenant/estado/instante).
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "22222222-2222-4222-8222-222222222222";
const ALVO = "33333333-3333-4333-8333-333333333333";
const OBS = "44444444-4444-4444-8444-444444444444";

const SOBERANA: ObservacaoSoberana = {
  id: OBS,
  organizationId: ORG,
  collaboratorId: ALVO,
  cycleId: CICLO,
  tipo: "POSITIVA",
  texto: "observacao ficticia",
  comunicado: false,
  comunicadoEm: null,
  excluida: false,
  motivoExclusao: null,
  autorUserProfileId: "55555555-5555-4555-8555-555555555555",
  autorCollaboratorId: null,
  version: 7,
  criadoEm: "2026-04-01T10:00:00.000Z",
  atualizadoEm: "2026-04-02T10:00:00.000Z",
};

interface Chamada {
  readonly metodo: string;
  readonly corpo: Record<string, unknown>;
}

function repositorioEspiao(
  chamadas: Chamada[],
  leitura: ResultadoObservacoes<ObservacaoSoberana>
): ObservationRepository {
  const registrar = (
    metodo: string,
    resposta: ResultadoObservacoes<unknown>
  ): ((...args: unknown[]) => Promise<ResultadoObservacoes<unknown>>) => {
    return (...args) => {
      // O controlador chama a porta com ARGUMENTOS POSICIONAIS em algumas
      // operações (ex.: listagem: `(organizationId, escopo, opcoes)`) e com um
      // único objeto em outras. O espião registra o que a chamada REALMENTE
      // transporta: o objeto de opções e os argumentos posicionais rotulados —
      // sem inventar campo e sem perder a prova de que nada de autoridade vai.
      const objeto = args.find(
        (arg) => typeof arg === "object" && arg !== null
      ) as Record<string, unknown> | undefined;
      const textos = args.filter((arg): arg is string => typeof arg === "string");
      const corpo: Record<string, unknown> = { ...(objeto ?? {}) };
      if (textos.length > 0) corpo.organizationId = textos[0];
      if (textos.length > 1) corpo.escopo = textos[1];
      chamadas.push({ metodo, corpo });
      return Promise.resolve(resposta);
    };
  };
  const mutacao: ResultadoObservacoes<unknown> = {
    ok: true,
    data: { observacaoId: OBS, version: 8 },
  };
  // Elenco explícito: cada método registra seu NOME (a asserção depende disso).
  return {
    listarObservacoesPorEscopo: registrar("listarObservacoesPorEscopo", {
      ok: true,
      data: { escopo: "SELF", selfCollaboratorId: ALVO, data: "2026-04-01T00:00:00.000Z", total: 0, itens: [] },
    }),
    obterObservacao: registrar("obterObservacao", leitura),
    obterHistoricoObservacao: registrar("obterHistoricoObservacao", {
      ok: true,
      data: {
        observacaoId: OBS,
        total: 1,
        eventos: [
          {
            id: "66666666-6666-4666-8666-666666666666",
            evento: "CRIADA",
            dataEfetiva: "2026-04-01T10:00:00.000Z",
            motivo: "Criacao de observacao",
            beforeValue: null,
            afterValue: { texto: "observacao ficticia" },
            payloadHash: "a".repeat(64),
            actorUserProfileId: "55555555-5555-4555-8555-555555555555",
            actorCollaboratorId: null,
            operationId: "77777777-7777-4777-8777-777777777777",
            criadoEm: "2026-04-01T10:00:00.000Z",
          },
        ],
      },
    }),
    criarObservacao: registrar("criarObservacao", mutacao),
    editarObservacao: registrar("editarObservacao", mutacao),
    definirComunicado: registrar("definirComunicado", mutacao),
    excluirObservacao: registrar("excluirObservacao", mutacao),
    revogarExclusao: registrar("revogarExclusao", mutacao),
  } as unknown as ObservationRepository;
}

function controlador(chamadas: Chamada[], leitura: ResultadoObservacoes<ObservacaoSoberana> = { ok: true, data: SOBERANA }) {
  let sequencia = 0;
  return criarControladorObservacoes({
    repositorio: repositorioEspiao(chamadas, leitura),
    gerarOperationId: () => {
      sequencia += 1;
      return `op-${sequencia}`;
    },
  });
}

describe("F5-11 P5 — controlador de observações soberanas", () => {
  it("criar gera `operationId` novo por chamada e NÃO lê versão (não há linha existente)", async () => {
    const chamadas: Chamada[] = [];
    const ctrl = controlador(chamadas);

    await ctrl.criar({ organizationId: ORG, cycleId: CICLO, collaboratorId: ALVO, tipo: "POSITIVA", texto: "a" });
    await ctrl.criar({ organizationId: ORG, cycleId: CICLO, collaboratorId: ALVO, tipo: "NEGATIVA", texto: "b" });

    expect(chamadas.map((c) => c.metodo)).toEqual(["criarObservacao", "criarObservacao"]);
    const ids = chamadas.map((c) => c.corpo.operationId);
    expect(ids[0]).toBe("op-1");
    expect(ids[1]).toBe("op-2");
    expect(chamadas[0].corpo).not.toHaveProperty("expectedVersion");
  });

  it("mutações de linha existente leem a versão SOBERANA e a enviam (nunca do usuário)", async () => {
    const chamadas: Chamada[] = [];
    const ctrl = controlador(chamadas);
    const resultado = await ctrl.editar({
      organizationId: ORG,
      observationId: OBS,
      tipo: "NEUTRA",
      texto: "novo",
      comunicado: true,
    });

    expect(resultado.ok).toBe(true);
    expect(chamadas.map((c) => c.metodo)).toEqual(["obterObservacao", "editarObservacao"]);
    expect(chamadas[1].corpo.expectedVersion).toBe(SOBERANA.version);
    expect(chamadas[0].corpo.operationId).toBe("op-1");
    expect(chamadas[1].corpo.operationId).toBe("op-2");
  });

  it("negação na LEITURA interrompe antes de qualquer mutação (fail-closed, sem tentativa otimista)", async () => {
    const chamadas: Chamada[] = [];
    const ctrl = controlador(chamadas, {
      ok: false,
      error: { code: "FORBIDDEN", message: "negado pelo servidor" },
    });

    const resultado = await ctrl.excluir({ organizationId: ORG, observationId: OBS, motivo: "motivo" });

    expect(resultado.ok).toBe(false);
    if (resultado.ok) throw new Error("esperado falha");
    expect(resultado.error.code).toBe("FORBIDDEN");
    expect(resultado.error.mensagem).toBe("Você não tem permissão para esta operação.");
    expect(chamadas.map((c) => c.metodo)).toEqual(["obterObservacao"]);
  });

  it("traduz o `CodigoPublico` e usa mensagem genérica para código sem mensagem específica", async () => {
    const chamadas: Chamada[] = [];
    const ctrl = controlador(chamadas, {
      ok: false,
      error: { code: "METHOD_NOT_ALLOWED", message: "detalhe do banco nao deve vazar" },
    });

    const resultado = await ctrl.definirComunicado({ organizationId: ORG, observationId: OBS, comunicado: true });
    if (resultado.ok) throw new Error("esperado falha");
    expect(resultado.error.mensagem).toBe("Não foi possível concluir a operação. Tente novamente.");
    expect(resultado.error.mensagem).not.toContain("detalhe do banco");
  });

  it("o payload NUNCA carrega autoridade declarada pelo chamador", async () => {
    const chamadas: Chamada[] = [];
    const ctrl = controlador(chamadas);

    await ctrl.criar({ organizationId: ORG, cycleId: CICLO, collaboratorId: ALVO, tipo: "POSITIVA", texto: "a" });
    await ctrl.definirComunicado({ organizationId: ORG, observationId: OBS, comunicado: true });
    await ctrl.revogar({ organizationId: ORG, observationId: OBS, motivo: "motivo" });

    const proibidas = [
      "actor_id",
      "actorId",
      "actor_user_profile_id",
      "authorUserProfileId",
      "authorCollaboratorId",
      "author_collaborator_id",
      "membership_id",
      "tenantId",
      "tenant_id",
      "status",
      "excluida",
      "comunicadoEm",
      "comunicado_em",
      "capability",
      "scope",
      "role",
      "domainState",
      "data",
      "instante",
      "payload_hash",
    ];
    for (const chamada of chamadas) {
      for (const proibida of proibidas) {
        expect(chamada.corpo).not.toHaveProperty(proibida);
      }
    }
  });

  it("a listagem por escopo transporta apenas organização, escopo e unidade opcional", async () => {
    const chamadas: Chamada[] = [];
    const ctrl = controlador(chamadas);
    await ctrl.listarPorEscopo(ORG, "DIRECT_REPORTS");
    expect(Object.keys(chamadas[0].corpo).sort()).toEqual(["escopo", "operationId", "organizationId"]);
    expect(chamadas[0].corpo).not.toHaveProperty("data");
  });

  it("o HISTÓRICO é lido pela trilha soberana, sem versão/mutação e com idempotência própria", async () => {
    const chamadas: Chamada[] = [];
    const ctrl = controlador(chamadas);

    const resultado = await ctrl.historico(ORG, OBS);

    expect(chamadas.map((c) => c.metodo)).toEqual(["obterHistoricoObservacao"]);
    expect(Object.keys(chamadas[0].corpo).sort()).toEqual([
      "observationId",
      "operationId",
      "organizationId",
    ]);
    // Leitura NÃO transporta `expectedVersion`, autoria, estado nem instante.
    for (const proibida of [
      "expectedVersion",
      "autor",
      "membership",
      "data",
      "status",
      "payloadHash",
    ]) {
      expect(chamadas[0].corpo).not.toHaveProperty(proibida);
    }
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) throw new Error("esperado sucesso");
    expect(resultado.data.total).toBe(1);
    expect(resultado.data.eventos).toHaveLength(1);
    expect(resultado.data.eventos[0].evento).toBe("CRIADA");
    // A projeção da trilha não inventa `actor_collaborator_id`.
    expect(resultado.data.eventos[0].actorCollaboratorId).toBeNull();
  });

  it("negação na LEITURA do histórico vira falha pública (fail-closed, sem trilha vazia)", async () => {
    const chamadas: Chamada[] = [];
    const ctrl = criarControladorObservacoes({
      repositorio: {
        ...repositorioEspiao(chamadas, { ok: true, data: SOBERANA }),
        obterHistoricoObservacao: (entrada: object) => {
          chamadas.push({
            metodo: "obterHistoricoObservacao",
            corpo: { ...entrada } as Record<string, unknown>,
          });
          return Promise.resolve({
            ok: false as const,
            error: { code: "FORBIDDEN" as const, message: "negado pelo servidor" },
          });
        },
      } as unknown as ObservationRepository,
      gerarOperationId: () => "op-historico",
    });

    const resultado = await ctrl.historico(ORG, OBS);

    expect(resultado.ok).toBe(false);
    if (resultado.ok) throw new Error("esperado falha");
    expect(resultado.error.code).toBe("FORBIDDEN");
    expect(resultado.error.mensagem).toBe("Você não tem permissão para esta operação.");
  });
});
