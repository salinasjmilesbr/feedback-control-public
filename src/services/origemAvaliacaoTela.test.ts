import { beforeEach, describe, expect, it } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock";
import {
  CHAVE_AVALIACOES_CORTADAS,
  CHAVE_CICLO_AVALIACOES,
  criarArmazenamentoMemoria,
  registrarAvaliacaoCortada,
  type ArmazenamentoCutover,
} from "../infrastructure/supabase/avaliacoes/cutover";
import { criarCutoverAvaliacoes } from "./avaliacoesSoberanas/cutoverAvaliacoesService";
import type { RepositorioAvaliacoes } from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes";
import {
  cacheConheciaComoTecnicaPostgres,
  ehCandidataAvaliacaoNova,
  lerAvaliacaoParaTela,
  resolverLeituraAvaliacao,
} from "./origemAvaliacaoTela";

/**
 * F5-06 (Issue #103) — DESCOBERTA SOBERANA da avaliação (correção pós-auditoria).
 *
 * A prova de existência vem do SERVIDOR. `localStorage` é cache/roteamento
 * OPCIONAL: apagá-lo, trocar de navegador/dispositivo, corromper o livro-caixa
 * ou abrir a URL diretamente NÃO pode esconder uma avaliação real do PostgreSQL.
 * Em contrapartida, uma falha de backend nunca vira leitura local silenciosa.
 */

const ORG_A = "11111111-1111-4111-8111-111111111111";
const ORG_B = "22222222-2222-4222-8222-222222222222";
const UUID_BANCO = "44444444-4444-4444-8444-444444444444";
const UUID_OUTRO_TENANT = "55555555-5555-4555-8555-555555555555";
const OCORRENCIA = "66666666-6666-4666-8666-666666666666";
const CHAVE_LEGADO = "feedback-control-feedbacks";

function painelFalso(evaluationId: string) {
  return {
    evaluationId,
    organizationId: ORG_A,
    cycleId: "77777777-7777-4777-8777-777777777777",
    cycleAno: 2026,
    cycleNumero: 1,
    configVersionId: "88888888-8888-4888-8888-888888888888",
    status: "RASCUNHO",
    evaluatedCollaboratorId: "99999999-9999-4999-8999-999999999999",
    meusPapeis: ["GESTAO_CADEIA"],
    participanteOcorrenciaId: OCORRENCIA,
    participanteRoleType: "GESTAO_CADEIA",
    participanteVigencia: { validFrom: "2026-01-01T00:00:00Z", validTo: null },
    criterios: [{ criterionId: "c-1", code: "c1", name: "Criterio", position: 0 }],
    subcriterios: [
      {
        subcriterionId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        code: "s1",
        name: "Sub",
        position: 0,
        criterionCode: "c1",
      },
    ],
    minhasNotas: [],
    meusComentarios: [],
    papeisComFeedbackFinal: [],
  };
}

function repositorioFalso(
  comportamentos: Partial<RepositorioAvaliacoes> = {}
): RepositorioAvaliacoes {
  const base: RepositorioAvaliacoes = {
    criar: async () => ({ ok: true, data: UUID_BANCO }),
    ler: async () => ({ ok: true, data: null }),
    gravarNotas: async () => ({ ok: true, data: null }),
    gravarComentario: async () => ({ ok: true, data: null }),
    concluir: async () => ({ ok: true, data: null }),
    reabrir: async () => ({ ok: true, data: null }),
    cancelar: async () => ({ ok: true, data: null }),
    realinharParticipantes: async () => ({ ok: true, data: 0 }),
    transparenciaDoAvaliado: async () => {
      throw new Error("não usado neste teste");
    },
    // O servidor só devolve a avaliação quando ela existe E é acessível no
    // tenant validado. Cross-tenant é indistinguível de inexistente.
    painelParticipante: async ({ evaluationId }) =>
      evaluationId === UUID_BANCO
        ? { ok: true, data: painelFalso(UUID_BANCO) }
        : { ok: false, error: { code: "NOT_FOUND", message: "não encontrada" } },
    resolverCiclo: async () => ({
      ok: true,
      data: "77777777-7777-4777-8777-777777777777",
    }),
  };
  return { ...base, ...comportamentos };
}

function deps(comportamentos: Partial<RepositorioAvaliacoes> = {}) {
  const repositorio = repositorioFalso(comportamentos);
  return {
    criarCutover: () =>
      criarCutoverAvaliacoes({
        repositorio,
        armazenamento: criarArmazenamentoMemoria(),
      }),
  };
}

function registroComEvidencia(): ArmazenamentoCutover {
  const registro = criarArmazenamentoMemoria();
  registrarAvaliacaoCortada(UUID_BANCO, registro);
  return registro;
}

describe("candidatura e cache (advisory)", () => {
  beforeEach(() => instalarLocalStorageEmMemoria());

  it("id não técnico nunca é candidato a avaliação nova", () => {
    expect(ehCandidataAvaliacaoNova("101")).toBe(false);
    expect(ehCandidataAvaliacaoNova("avaliacao-legada")).toBe(false);
    expect(ehCandidataAvaliacaoNova(undefined)).toBe(false);
  });

  it("id técnico é candidato mesmo SEM livro-caixa (a prova é do servidor)", () => {
    expect(ehCandidataAvaliacaoNova(UUID_BANCO)).toBe(true);
    expect(cacheConheciaComoTecnicaPostgres(UUID_BANCO)).toBe(false);
  });
});

describe("resolverLeituraAvaliacao (soberano-first)", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(CHAVE_LEGADO, JSON.stringify([]));
  });

  it("1) avaliação PostgreSQL acessível COM livro-caixa ⇒ POSTGRES", async () => {
    const resultado = await resolverLeituraAvaliacao(
      {
        organizationId: ORG_A,
        evaluationId: UUID_BANCO,
        registroCutover: registroComEvidencia(),
      },
      deps()
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.leitura?.origem).toBe("POSTGRES");
    if (resultado.leitura?.origem !== "POSTGRES") return;
    expect(resultado.leitura.painel.participanteOcorrenciaId).toBe(OCORRENCIA);
    expect(resultado.leitura.cacheConhecia).toBe(true);
  });

  it("2) avaliação PostgreSQL acessível SEM livro-caixa ⇒ POSTGRES", async () => {
    // Nenhuma evidência registrada: é exatamente o caso "outro navegador".
    const resultado = await resolverLeituraAvaliacao(
      { organizationId: ORG_A, evaluationId: UUID_BANCO },
      deps()
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.leitura?.origem).toBe("POSTGRES");
    if (resultado.leitura?.origem !== "POSTGRES") return;
    expect(resultado.leitura.cacheConhecia).toBe(false);
  });

  it("3) avaliação PostgreSQL acessível depois de LIMPAR o localStorage", async () => {
    const registro = registroComEvidencia();
    // Simula "limpar dados do site" no navegador.
    localStorage.clear();

    const resultado = await resolverLeituraAvaliacao(
      { organizationId: ORG_A, evaluationId: UUID_BANCO, registroCutover: registro },
      deps()
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.leitura?.origem).toBe("POSTGRES");
  });

  it("4) URL direta de avaliação PostgreSQL funciona sem estado local prévio", async () => {
    // Sem acervo legado, sem livro-caixa, sem índice: apenas o id da URL.
    localStorage.clear();

    const resultado = await lerAvaliacaoParaTela(
      { organizationId: ORG_A, evaluationId: UUID_BANCO },
      deps()
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.leitura?.origem).toBe("POSTGRES");
  });

  it("5) UUID legado sem correspondente no banco continua LEGADO_LOCAL", async () => {
    const idLegadoUuid = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
    localStorage.setItem(
      CHAVE_LEGADO,
      JSON.stringify([{ id: idLegadoUuid, status: "CONCLUIDA" }])
    );

    const resultado = await resolverLeituraAvaliacao(
      { organizationId: ORG_A, evaluationId: idLegadoUuid },
      deps()
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.leitura?.origem).toBe("LEGADO_LOCAL");
  });

  it("6) UUID cross-tenant não revela existência (NOT_FOUND indistinguível)", async () => {
    const outroTenant = await resolverLeituraAvaliacao(
      { organizationId: ORG_B, evaluationId: UUID_OUTRO_TENANT },
      deps()
    );
    const inexistente = await resolverLeituraAvaliacao(
      { organizationId: ORG_B, evaluationId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc" },
      deps()
    );

    expect(outroTenant).toEqual(inexistente);
    expect(outroTenant.ok).toBe(true);
    if (!outroTenant.ok) return;
    expect(outroTenant.leitura).toBeNull();
  });

  it("6b) avaliação cortada inacessível não é rebaixada a legado homônimo", async () => {
    // O servidor responde SEM conteúdo (sem ocorrência vigente do ator): não há
    // painel, e o registro legado homônimo NÃO é usado ⇒ fail-closed.
    localStorage.setItem(
      CHAVE_LEGADO,
      JSON.stringify([{ id: UUID_BANCO, status: "CONCLUIDA" }])
    );

    const resultado = await resolverLeituraAvaliacao(
      {
        organizationId: ORG_A,
        evaluationId: UUID_BANCO,
        registroCutover: registroComEvidencia(),
      },
      deps({ painelParticipante: async () => ({ ok: true, data: null as never }) })
    );

    expect(resultado.ok).toBe(false);
  });

  it("7) erro de backend não cai silenciosamente para o legado", async () => {
    localStorage.setItem(
      CHAVE_LEGADO,
      JSON.stringify([{ id: UUID_BANCO, status: "CONCLUIDA" }])
    );

    for (const comportamento of [
      { ok: false as const, error: { code: "FORBIDDEN" as const, message: "negado" } },
      { ok: false as const, error: { code: "INTERNAL" as const, message: "falha" } },
    ]) {
      const resultado = await resolverLeituraAvaliacao(
        {
          organizationId: ORG_A,
          evaluationId: UUID_BANCO,
          registroCutover: registroComEvidencia(),
        },
        deps({ painelParticipante: async () => comportamento })
      );

      expect(resultado.ok).toBe(false);
    }
  });

  it("7b) NOT_FOUND com id legado homônimo usa o legado; indeterminação não", async () => {
    const idLegadoUuid = UUID_OUTRO_TENANT;
    localStorage.setItem(
      CHAVE_LEGADO,
      JSON.stringify([{ id: idLegadoUuid, status: "RASCUNHO" }])
    );

    // Resposta do servidor "não existe no banco" ⇒ o registro legado homônimo
    // continua acessível (compatibilidade do acervo anterior ao cutover).
    const naoExiste = await resolverLeituraAvaliacao(
      { organizationId: ORG_A, evaluationId: idLegadoUuid },
      deps()
    );
    expect(naoExiste.ok).toBe(true);
    if (!naoExiste.ok) return;
    expect(naoExiste.leitura?.origem).toBe("LEGADO_LOCAL");

    // Indeterminação (falha real) NÃO cai para o legado.
    const indeterminado = await resolverLeituraAvaliacao(
      { organizationId: ORG_A, evaluationId: idLegadoUuid },
      deps({
        painelParticipante: async () => ({
          ok: false,
          error: { code: "INTERNAL", message: "indisponível" },
        }),
      })
    );
    expect(indeterminado.ok).toBe(false);
  });

  it("sem caminho soberano configurado, id técnico é recusado (nunca legado)", async () => {
    localStorage.setItem(
      CHAVE_LEGADO,
      JSON.stringify([{ id: UUID_BANCO, status: "RASCUNHO" }])
    );

    const resultado = await resolverLeituraAvaliacao(
      {
        organizationId: ORG_A,
        evaluationId: UUID_BANCO,
        registroCutover: registroComEvidencia(),
      },
      { criarCutover: () => null }
    );

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.erro).toContain("PostgreSQL");
  });

  it("nenhum caminho destes grava no acervo legado nem cria índice", async () => {
    const antes = localStorage.getItem(CHAVE_LEGADO);

    await resolverLeituraAvaliacao(
      { organizationId: ORG_A, evaluationId: UUID_BANCO },
      deps()
    );
    await resolverLeituraAvaliacao(
      {
        organizationId: ORG_A,
        evaluationId: UUID_BANCO,
        registroCutover: registroComEvidencia(),
      },
      deps()
    );
    await resolverLeituraAvaliacao(
      { organizationId: ORG_A, evaluationId: "101" },
      deps()
    );

    expect(localStorage.getItem(CHAVE_LEGADO)).toBe(antes);
    expect(localStorage.getItem(CHAVE_CICLO_AVALIACOES)).toBeNull();
    expect(localStorage.getItem(CHAVE_AVALIACOES_CORTADAS)).toBeNull();
  });
});
