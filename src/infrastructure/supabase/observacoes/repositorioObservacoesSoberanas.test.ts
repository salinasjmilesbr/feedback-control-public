import { describe, expect, it } from "vitest";

import fonteRepositorio from "./repositorioObservacoesSoberanas.ts?raw";
import { CHAVES_POR_OPERACAO, type OperacaoObservacao } from "./contrato";
import type { EdgeObservacoes, ResultadoEdgeObservacoes } from "./edgeObservacoes";
import { criarRepositorioObservacoesSoberanas } from "./repositorioObservacoesSoberanas";

/**
 * F5-11 P5 (Issue #250), L1 — a implementação da porta de observações passa
 * EXCLUSIVAMENTE pelo adapter da Edge, com a OPERAÇÃO certa por método e o corpo
 * com EXATAMENTE as chaves derivadas do contrato real (nada de literal digitado
 * à mão para nome de operação/campos).
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "22222222-2222-4222-8222-222222222222";
const ALVO = "33333333-3333-4333-8333-333333333333";
const OBS = "44444444-4444-4444-8444-444444444444";

/** `snake_case` → `camelCase` (derivação, não literal). */
function camel(chave: string): string {
  return chave.replace(/_([a-z])/g, (_t, letra: string) => letra.toUpperCase());
}

/** Método ESPERADO do adapter, derivado da operação do contrato. */
function metodoDaOperacao(operacao: OperacaoObservacao): string {
  return camel(operacao.slice("observacao.".length));
}

/** Chaves ESPERADAS no corpo, derivadas da allowlist real do contrato. */
function chavesDaOperacao(operacao: OperacaoObservacao): readonly string[] {
  return CHAVES_POR_OPERACAO[operacao]
    .filter((chave) => chave !== "operacao")
    .map(camel)
    .sort();
}

interface Registro {
  readonly metodo: string;
  readonly corpo: Record<string, unknown>;
}

function edgeEspiao(
  registros: Registro[],
  resposta: () => ResultadoEdgeObservacoes<unknown>
): EdgeObservacoes {
  const registrar = (metodo: string) => {
    return (entrada: object): Promise<ResultadoEdgeObservacoes<unknown>> => {
      registros.push({ metodo, corpo: { ...entrada } as Record<string, unknown> });
      return Promise.resolve(resposta());
    };
  };
  return {
    criar: registrar("criar"),
    editar: registrar("editar"),
    definirComunicado: registrar("definirComunicado"),
    excluir: registrar("excluir"),
    revogar: registrar("revogar"),
    obter: registrar("obter"),
    listarPorEscopo: registrar("listarPorEscopo"),
    historico: registrar("historico"),
  };
}

function linhaSoberana(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    observation_id: OBS,
    organization_id: ORG,
    collaborator_id: ALVO,
    cycle_id: CICLO,
    tipo: "POSITIVA",
    texto: "observacao ficticia de teste",
    comunicado: false,
    comunicado_em: null,
    excluida: false,
    motivo_exclusao: null,
    author_user_profile_id: "55555555-5555-4555-8555-555555555555",
    author_collaborator_id: null,
    version: 3,
    created_at: "2026-04-01T10:00:00.000Z",
    updated_at: "2026-04-02T10:00:00.000Z",
    ...extra,
  };
}

const MUTACAO_OK: ResultadoEdgeObservacoes<unknown> = {
  ok: true,
  data: { observation_id: OBS, version: 1, criada: true, idempotente: false },
};

describe("F5-11 P5 — repositório soberano de observações (sobre o adapter da Edge)", () => {
  it("cada operação chama o MÉTODO certo do adapter e envia as chaves EXATAS do contrato", async () => {
    const registros: Registro[] = [];
    const repo = criarRepositorioObservacoesSoberanas(edgeEspiao(registros, () => MUTACAO_OK));

    await repo.criarObservacao({ organizationId: ORG, cycleId: CICLO, collaboratorId: ALVO, tipo: "POSITIVA", texto: "texto" });
    await repo.editarObservacao({ organizationId: ORG, observationId: OBS, tipo: "NEUTRA", texto: "texto", comunicado: true, expectedVersion: 3 });
    await repo.definirComunicado({ organizationId: ORG, observationId: OBS, comunicado: true, expectedVersion: 3 });
    await repo.excluirObservacao({ organizationId: ORG, observationId: OBS, motivo: "motivo", expectedVersion: 3 });
    await repo.revogarExclusao({ organizationId: ORG, observationId: OBS, motivo: "motivo", expectedVersion: 3 });

    const operacoes: readonly OperacaoObservacao[] = [
      "observacao.criar",
      "observacao.editar",
      "observacao.definir_comunicado",
      "observacao.excluir",
      "observacao.revogar",
    ];

    expect(registros.map((r) => r.metodo)).toEqual(operacoes.map(metodoDaOperacao));
    for (let i = 0; i < operacoes.length; i += 1) {
      expect(Object.keys(registros[i].corpo).sort()).toEqual(chavesDaOperacao(operacoes[i]));
    }
  });

  it("as leituras usam `obter`/`listarPorEscopo` e a listagem exige `escopo` (unidade é opcional)", async () => {
    const registros: Registro[] = [];
    const comEscopo: ResultadoEdgeObservacoes<unknown> = {
      ok: true,
      data: { escopo: "DIRECT_REPORTS", self_collaborator_id: null, data: "2026-04-01T00:00:00.000Z", total: 1, itens: [linhaSoberana()] },
    };
    const repo = criarRepositorioObservacoesSoberanas(edgeEspiao(registros, () => comEscopo));

    await repo.listarObservacoesPorEscopo(ORG, "DIRECT_REPORTS");
    const semUnidade = registros[0].corpo;
    expect(registros[0].metodo).toBe(metodoDaOperacao("observacao.listar_por_escopo"));
    expect(Object.keys(semUnidade).sort()).toEqual(
      chavesDaOperacao("observacao.listar_por_escopo").filter((chave) => chave !== "organizationalUnitId")
    );
    expect(semUnidade.escopo).toBe("DIRECT_REPORTS");
    expect(semUnidade).not.toHaveProperty("data");
    expect(semUnidade).not.toHaveProperty("organization_id");

    await repo.listarObservacoesPorEscopo(ORG, "SELF", { organizationalUnitId: ALVO });
    expect(registros[1].corpo.organizationalUnitId).toBe(ALVO);

    const registrosLeitura: Registro[] = [];
    const repoObter = criarRepositorioObservacoesSoberanas(
      edgeEspiao(registrosLeitura, () => ({ ok: true, data: linhaSoberana() }))
    );
    const obtida = await repoObter.obterObservacao({ organizationId: ORG, observationId: OBS });
    expect(registrosLeitura[0].metodo).toBe(metodoDaOperacao("observacao.obter"));
    expect(Object.keys(registrosLeitura[0].corpo).sort()).toEqual(chavesDaOperacao("observacao.obter"));
    expect(obtida.ok).toBe(true);
  });

  it("projeta a linha soberana SEM inventar campo e mantém o UUID como identidade", async () => {
    const repo = criarRepositorioObservacoesSoberanas(
      edgeEspiao([], () => ({ ok: true, data: linhaSoberana() }))
    );
    const resultado = await repo.obterObservacao({ organizationId: ORG, observationId: OBS });
    if (!resultado.ok) throw new Error("esperado sucesso");
    expect(resultado.data).toEqual({
      id: OBS,
      organizationId: ORG,
      collaboratorId: ALVO,
      cycleId: CICLO,
      tipo: "POSITIVA",
      texto: "observacao ficticia de teste",
      comunicado: false,
      comunicadoEm: null,
      excluida: false,
      motivoExclusao: null,
      autorUserProfileId: "55555555-5555-4555-8555-555555555555",
      autorCollaboratorId: null,
      version: 3,
      criadoEm: "2026-04-01T10:00:00.000Z",
      atualizadoEm: "2026-04-02T10:00:00.000Z",
    });
  });

  it("é fail-closed: erro do adapter passa com o MESMO código público e sem dado", async () => {
    const repo = criarRepositorioObservacoesSoberanas(
      edgeEspiao([], () => ({ ok: false, error: { code: "FORBIDDEN", message: "negado" } }))
    );
    const resultado = await repo.obterObservacao({ organizationId: ORG, observationId: OBS });
    expect(resultado).toEqual({ ok: false, error: { code: "FORBIDDEN", message: "negado" } });
  });

  it("resposta fora do contrato vira INTERNAL (nunca ausência silenciosa nem dado inventado)", async () => {
    const repoInvalido = criarRepositorioObservacoesSoberanas(
      edgeEspiao([], () => ({ ok: true, data: { observation_id: "nao-e-uuid", version: 1 } }))
    );
    const obter = await repoInvalido.obterObservacao({ organizationId: ORG, observationId: OBS });
    expect(obter.ok).toBe(false);
    if (obter.ok) throw new Error("esperado falha");
    expect(obter.error.code).toBe("INTERNAL");

    const repoEscopoInvalido = criarRepositorioObservacoesSoberanas(
      edgeEspiao([], () => ({ ok: true, data: { escopo: "ORGANIZATION", itens: [] } }))
    );
    const listar = await repoEscopoInvalido.listarObservacoesPorEscopo(ORG, "SELF");
    expect(listar.ok).toBe(false);
  });

  it("linha fora do contrato é DESCARTADA da listagem (sem completar valor faltante)", async () => {
    const repo = criarRepositorioObservacoesSoberanas(
      edgeEspiao([], () => ({
        ok: true,
        data: {
          escopo: "SELF",
          self_collaborator_id: ALVO,
          data: "2026-04-01T00:00:00.000Z",
          total: 2,
          itens: [linhaSoberana(), { observation_id: OBS, tipo: "POSITIVA" }],
        },
      }))
    );
    const lista = await repo.listarObservacoesPorEscopo(ORG, "SELF");
    if (!lista.ok) throw new Error("esperado sucesso");
    expect(lista.data.itens).toHaveLength(1);
    expect(lista.data.itens[0].id).toBe(OBS);
    expect(lista.data.selfCollaboratorId).toBe(ALVO);
  });

  it("gera `operationId` novo por chamada e respeita o informado (idempotência D10)", async () => {
    const registros: Registro[] = [];
    const repo = criarRepositorioObservacoesSoberanas(edgeEspiao(registros, () => MUTACAO_OK));
    await repo.criarObservacao({ organizationId: ORG, cycleId: CICLO, collaboratorId: ALVO, tipo: "POSITIVA", texto: "a" });
    await repo.criarObservacao({ organizationId: ORG, cycleId: CICLO, collaboratorId: ALVO, tipo: "POSITIVA", texto: "b" });
    await repo.criarObservacao({ organizationId: ORG, cycleId: CICLO, collaboratorId: ALVO, tipo: "POSITIVA", texto: "c", operationId: "id-fixo" });

    const ids = registros.map((r) => r.corpo.operationId);
    expect(typeof ids[0]).toBe("string");
    expect((ids[0] as string).length).toBeGreaterThan(0);
    expect(ids[0]).not.toBe(ids[1]);
    expect(ids[2]).toBe("id-fixo");
  });

  it("mutações de linha existente enviam `expectedVersion` (contrato D10) e nunca estado/autoridade", async () => {
    const registros: Registro[] = [];
    const repo = criarRepositorioObservacoesSoberanas(edgeEspiao(registros, () => MUTACAO_OK));
    await repo.editarObservacao({ organizationId: ORG, observationId: OBS, tipo: "NEGATIVA", texto: "t", comunicado: false, expectedVersion: 9 });
    const corpo = registros[0].corpo;
    expect(corpo.expectedVersion).toBe(9);
    for (const proibida of ["actor_id", "actorId", "author_collaborator_id", "authorCollaboratorId", "status", "excluida", "comunicado_em", "capability", "domainState", "data", "instante", "payload_hash"]) {
      expect(corpo).not.toHaveProperty(proibida);
    }
  });

  it("o FONTE não contém `.rpc(`/credencial de serviço/storage local nem acesso a tabela", () => {
    // Código SEM comentários (bloco e linha — mesma semântica de `apenasCodigo`
    // em `src/authorization/estruturaUiSeguranca.test.ts`); strings NÃO são
    // removidas, então literal proibido em código continua reprovando.
    const apenasCodigo = (fonte: string): string =>
      fonte
        .replace(/\/\*[\s\S]*?\*\//g, "")
        .split("\n")
        .map((linha) => {
          const indice = linha.indexOf("//");
          return indice === -1 ? linha : linha.slice(0, indice);
        })
        .join("\n");
    const codigoRepositorio = apenasCodigo(fonteRepositorio);
    expect(codigoRepositorio).not.toMatch(/\.rpc\s*\(/);
    expect(codigoRepositorio).not.toMatch(/SERVICE_ROLE_KEY|serviceRoleKey/);
    expect(codigoRepositorio).not.toMatch(/localStorage|sessionStorage/);
    expect(codigoRepositorio).not.toMatch(/\.from\s*\(/);
  });
});

/** Evento REAL da projeção de `observacao_historico` (P2). */
function eventoHistorico(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    event_id: "66666666-6666-4666-8666-666666666666",
    event_type: "EDITADA",
    effective_date: "2026-04-02T11:00:00.000Z",
    reason: "Edicao da definicao da observacao",
    before_value: { tipo: "POSITIVA", texto: "texto anterior ficticio", version: 1 },
    after_value: { tipo: "NEGATIVA", texto: "texto atual ficticio", version: 2 },
    payload_hash: "c".repeat(64),
    actor_user_profile_id: "55555555-5555-4555-8555-555555555555",
    actor_membership_id: "77777777-7777-4777-8777-777777777777",
    operation_id: "88888888-8888-4888-8888-888888888888",
    created_at: "2026-04-02T11:00:00.000Z",
    ...extra,
  };
}

function envelopeHistorico(
  eventos: readonly unknown[],
  extra: Record<string, unknown> = {}
): Record<string, unknown> {
  return { observation_id: OBS, total: eventos.length, eventos, ...extra };
}

describe("F5-11 P5 L3 — leitura soberana da TRILHA (`observacao.historico`)", () => {
  it("usa o método `historico` do adapter com as chaves EXATAS do contrato", async () => {
    const registros: Registro[] = [];
    const repo = criarRepositorioObservacoesSoberanas(
      edgeEspiao(registros, () => ({
        ok: true,
        data: envelopeHistorico([eventoHistorico()]),
      }))
    );

    await repo.obterHistoricoObservacao({ organizationId: ORG, observationId: OBS });

    expect(registros[0].metodo).toBe(metodoDaOperacao("observacao.historico"));
    expect(Object.keys(registros[0].corpo).sort()).toEqual(
      chavesDaOperacao("observacao.historico")
    );
    // A LEITURA não transporta versão, autoria, estado nem instante (D21).
    for (const proibida of ["expectedVersion", "data", "status", "actorId", "payloadHash"]) {
      expect(registros[0].corpo).not.toHaveProperty(proibida);
    }
  });

  it("projeta o evento da trilha SEM inventar campo (`actor_collaborator_id` é `null`)", async () => {
    const repo = criarRepositorioObservacoesSoberanas(
      edgeEspiao([], () => ({
        ok: true,
        data: envelopeHistorico([eventoHistorico()]),
      }))
    );

    const resultado = await repo.obterHistoricoObservacao({
      organizationId: ORG,
      observationId: OBS,
    });
    if (!resultado.ok) throw new Error("esperado sucesso");

    expect(resultado.data).toEqual({
      observacaoId: OBS,
      total: 1,
      eventos: [
        {
          id: "66666666-6666-4666-8666-666666666666",
          evento: "EDITADA",
          dataEfetiva: "2026-04-02T11:00:00.000Z",
          motivo: "Edicao da definicao da observacao",
          beforeValue: { tipo: "POSITIVA", texto: "texto anterior ficticio", version: 1 },
          afterValue: { tipo: "NEGATIVA", texto: "texto atual ficticio", version: 2 },
          payloadHash: "c".repeat(64),
          actorUserProfileId: "55555555-5555-4555-8555-555555555555",
          actorCollaboratorId: null,
          operationId: "88888888-8888-4888-8888-888888888888",
          criadoEm: "2026-04-02T11:00:00.000Z",
        },
      ],
    });
  });

  it("evento fora do contrato é DESCARTADO (event_type desconhecido, UUID inválido, imagem escalar)", async () => {
    const repo = criarRepositorioObservacoesSoberanas(
      edgeEspiao([], () => ({
        ok: true,
        data: envelopeHistorico([
          eventoHistorico(),
          eventoHistorico({ event_type: "EVENTO_INVENTADO" }),
          eventoHistorico({ event_id: "nao-e-uuid" }),
          eventoHistorico({ before_value: "texto-solto" }),
        ]),
      }))
    );

    const resultado = await repo.obterHistoricoObservacao({
      organizationId: ORG,
      observationId: OBS,
    });
    if (!resultado.ok) throw new Error("esperado sucesso");
    expect(resultado.data.eventos).toHaveLength(1);
    expect(resultado.data.eventos[0].evento).toBe("EDITADA");
  });

  it("`before_value` nulo é FATO (criação sem imagem), não descarte", async () => {
    const repo = criarRepositorioObservacoesSoberanas(
      edgeEspiao([], () => ({
        ok: true,
        data: envelopeHistorico([
          eventoHistorico({
            event_type: "CRIADA",
            reason: "Criacao de observacao",
            before_value: null,
          }),
        ]),
      }))
    );

    const resultado = await repo.obterHistoricoObservacao({
      organizationId: ORG,
      observationId: OBS,
    });
    if (!resultado.ok) throw new Error("esperado sucesso");
    expect(resultado.data.eventos[0].beforeValue).toBeNull();
    expect(resultado.data.eventos[0].evento).toBe("CRIADA");
  });

  it("envelope com alvo DIVERGENTE do pedido vira INTERNAL (nunca trilha de outra observação)", async () => {
    const repo = criarRepositorioObservacoesSoberanas(
      edgeEspiao([], () => ({
        ok: true,
        data: envelopeHistorico([eventoHistorico()], {
          observation_id: "99999999-9999-4999-8999-999999999999",
        }),
      }))
    );

    const resultado = await repo.obterHistoricoObservacao({
      organizationId: ORG,
      observationId: OBS,
    });
    expect(resultado.ok).toBe(false);
    if (resultado.ok) throw new Error("esperado falha");
    expect(resultado.error.code).toBe("INTERNAL");
  });

  it("é fail-closed: erro do adapter na trilha passa com o MESMO código público e sem dado", async () => {
    const repo = criarRepositorioObservacoesSoberanas(
      edgeEspiao([], () => ({ ok: false, error: { code: "FORBIDDEN", message: "negado" } }))
    );

    const resultado = await repo.obterHistoricoObservacao({
      organizationId: ORG,
      observationId: OBS,
    });
    expect(resultado).toEqual({
      ok: false,
      error: { code: "FORBIDDEN", message: "negado" },
    });
  });
});
