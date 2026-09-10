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
  classificarOrigem,
  ehAvaliacaoNova,
  lerAvaliacaoParaTela,
} from "./origemAvaliacaoTela";

/**
 * F5-06 (Issue #103) — ORIGEM da avaliação para as telas (correção pós-auditoria).
 *
 * A origem NÃO pode ser inferida pelo FORMATO do id nem por data: `POSTGRES`
 * exige EVIDÊNCIA ESTRUTURAL de cutover (registro de escrita server-side
 * confirmada). Um id legado que por acaso tenha forma de UUID continua
 * `LEGADO_LOCAL` (fail-closed), e ausência/corrupção da evidência nunca promove
 * nada automaticamente.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const UUID_LEGADO = "33333333-3333-4333-8333-333333333333";
const UUID_CORTADO = "44444444-4444-4444-8444-444444444444";
const OCORRENCIA = "55555555-5555-4555-8555-555555555555";
const CHAVE_LEGADO = "feedback-control-feedbacks";

function repositorioFalso(
  comportamentos: Partial<RepositorioAvaliacoes> = {}
): RepositorioAvaliacoes {
  const base: RepositorioAvaliacoes = {
    criar: async () => ({ ok: true, data: UUID_CORTADO }),
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
    painelParticipante: async () => ({
      ok: true,
      data: {
        evaluationId: UUID_CORTADO,
        organizationId: ORG,
        cycleId: "22222222-2222-4222-8222-222222222222",
        cycleAno: 2026,
        cycleNumero: 1,
        configVersionId: "77777777-7777-4777-8777-777777777777",
        status: "RASCUNHO",
        evaluatedCollaboratorId: "88888888-8888-4888-8888-888888888888",
        meusPapeis: ["GESTAO_CADEIA"],
        participanteOcorrenciaId: OCORRENCIA,
        participanteRoleType: "GESTAO_CADEIA",
        participanteVigencia: { validFrom: "2026-01-01T00:00:00Z", validTo: null },
        criterios: [
          { criterionId: "c-1", code: "c1", name: "Criterio", position: 0 },
        ],
        subcriterios: [
          {
            subcriterionId: "66666666-6666-4666-8666-666666666666",
            code: "s1",
            name: "Sub",
            position: 0,
            criterionCode: "c1",
          },
        ],
        minhasNotas: [],
        meusComentarios: [],
        papeisComFeedbackFinal: [],
      },
    }),
    resolverCiclo: async () => ({
      ok: true,
      data: "22222222-2222-4222-8222-222222222222",
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

/** Registro de cutover com a evidência da escrita soberana confirmada. */
function registroComEvidencia(): ArmazenamentoCutover {
  const registro = criarArmazenamentoMemoria();
  registrarAvaliacaoCortada(UUID_CORTADO, registro);
  return registro;
}

describe("classificarOrigem / ehAvaliacaoNova (por EVIDÊNCIA, nunca por formato)", () => {
  // O registro do ambiente é isolado por teste: a classificação padrão também
  // consulta o `localStorage`, e um teste não pode herdar evidência de outro.
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
  });

  it("1) id legado numérico ⇒ LEGADO_LOCAL", () => {
    expect(classificarOrigem("101", registroComEvidencia())).toBe("LEGADO_LOCAL");
    expect(ehAvaliacaoNova("101", registroComEvidencia())).toBe(false);
  });

  it("2) id legado textual ⇒ LEGADO_LOCAL", () => {
    expect(classificarOrigem("avaliacao-legada-1", registroComEvidencia())).toBe(
      "LEGADO_LOCAL"
    );
    expect(ehAvaliacaoNova("avaliacao-legada-1", registroComEvidencia())).toBe(false);
  });

  it("3) id legado com FORMATO de UUID, mas sem registro de cutover ⇒ LEGADO_LOCAL", () => {
    // Este é o bloqueador da auditoria: formato de UUID NÃO é evidência.
    expect(classificarOrigem(UUID_LEGADO)).toBe("LEGADO_LOCAL");
    expect(ehAvaliacaoNova(UUID_LEGADO)).toBe(false);
    // Nem mesmo quando o registro contém OUTRA avaliação.
    expect(classificarOrigem(UUID_LEGADO, registroComEvidencia())).toBe(
      "LEGADO_LOCAL"
    );
  });

  it("4) UUID registrado por escrita soberana confirmada ⇒ POSTGRES", () => {
    expect(classificarOrigem(UUID_CORTADO, registroComEvidencia())).toBe("POSTGRES");
    expect(ehAvaliacaoNova(UUID_CORTADO, registroComEvidencia())).toBe(true);
  });

  it("5) livro-caixa ausente/corrompido NÃO promove UUID automaticamente", () => {
    // Ausente: sem armazenamento informado e com registro vazio.
    expect(classificarOrigem(UUID_CORTADO, null)).toBe("LEGADO_LOCAL");
    expect(classificarOrigem(UUID_CORTADO, criarArmazenamentoMemoria())).toBe(
      "LEGADO_LOCAL"
    );

    // Corrompido: JSON inválido, tipo errado e id não técnico. NENHUM caso pode
    // promover o UUID_CORTADO (que nunca aparece como evidência válida).
    for (const conteudo of [
      "{nao-e-json",
      JSON.stringify({ a: 1 }),
      JSON.stringify([UUID_LEGADO]),
      JSON.stringify(["nao-e-uuid", UUID_LEGADO]),
      JSON.stringify([]),
    ]) {
      const registro = criarArmazenamentoMemoria();
      registro.setItem(CHAVE_AVALIACOES_CORTADAS, conteudo);
      expect(classificarOrigem(UUID_CORTADO, registro)).toBe("LEGADO_LOCAL");
    }

    // O que ESTÁ registrado como evidência válida é reconhecido — o id de outro
    // registro legado (mesmo UUID) continua legado.
    const registroComLegado = criarArmazenamentoMemoria();
    registroComLegado.setItem(
      CHAVE_AVALIACOES_CORTADAS,
      JSON.stringify([UUID_CORTADO])
    );
    expect(classificarOrigem(UUID_CORTADO, registroComLegado)).toBe("POSTGRES");
    expect(classificarOrigem(UUID_LEGADO, registroComLegado)).toBe("LEGADO_LOCAL");
  });

  it("id ausente/vazio ⇒ LEGADO_LOCAL (nunca promove por omissão)", () => {
    expect(classificarOrigem(undefined, registroComEvidencia())).toBe("LEGADO_LOCAL");
    expect(classificarOrigem("", registroComEvidencia())).toBe("LEGADO_LOCAL");
    expect(classificarOrigem("   ", registroComEvidencia())).toBe("LEGADO_LOCAL");
  });

  it("a marca registrada é idempotente e ignora id não técnico", () => {
    const registro = criarArmazenamentoMemoria();
    registrarAvaliacaoCortada(UUID_CORTADO, registro);
    registrarAvaliacaoCortada(UUID_CORTADO, registro);
    registrarAvaliacaoCortada("nao-e-uuid", registro);

    expect(classificarOrigem(UUID_CORTADO, registro)).toBe("POSTGRES");
    expect(classificarOrigem("nao-e-uuid", registro)).toBe("LEGADO_LOCAL");
  });
});

describe("lerAvaliacaoParaTela", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
    localStorage.setItem(
      CHAVE_LEGADO,
      JSON.stringify([
        { id: "avaliacao-legada", status: "RASCUNHO" },
        { id: UUID_LEGADO, status: "CONCLUIDA" },
      ])
    );
  });

  it("id legado é lido do acervo LEGADO (somente leitura)", async () => {
    const resultado = await lerAvaliacaoParaTela(
      { organizationId: ORG, evaluationId: "avaliacao-legada" },
      deps()
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.leitura?.origem).toBe("LEGADO_LOCAL");
    expect(resultado.leitura?.painel).toBeUndefined();
  });

  it("UUID LEGADO é lido do acervo local (não é promovido a POSTGRES)", async () => {
    const resultado = await lerAvaliacaoParaTela(
      { organizationId: ORG, evaluationId: UUID_LEGADO },
      deps()
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.leitura?.origem).toBe("LEGADO_LOCAL");
    expect(resultado.leitura?.painel).toBeUndefined();
  });

  it("id local inexistente devolve leitura vazia (sem inventar registro)", async () => {
    const resultado = await lerAvaliacaoParaTela(
      { organizationId: ORG, evaluationId: "nao-existe" },
      deps()
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.leitura).toBeNull();
  });

  it("UUID com evidência de cutover é lido do BANCO e nunca do legado", async () => {
    const resultado = await lerAvaliacaoParaTela(
      {
        organizationId: ORG,
        evaluationId: UUID_CORTADO,
        registroCutover: registroComEvidencia(),
      },
      deps()
    );

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    expect(resultado.leitura?.origem).toBe("POSTGRES");
    expect(resultado.leitura?.painel?.participanteOcorrenciaId).toBe(OCORRENCIA);
  });

  it("6) erro de leitura do banco em avaliação CORTADA ⇒ fail-closed, sem fallback legado", async () => {
    // Mesmo existindo um registro local com o MESMO id, a leitura soberana
    // recusada NÃO cai para o acervo legado.
    localStorage.setItem(
      CHAVE_LEGADO,
      JSON.stringify([{ id: UUID_CORTADO, status: "RASCUNHO" }])
    );

    const resultado = await lerAvaliacaoParaTela(
      {
        organizationId: ORG,
        evaluationId: UUID_CORTADO,
        registroCutover: registroComEvidencia(),
      },
      deps({
        painelParticipante: async () => ({
          ok: false,
          error: { code: "FORBIDDEN", message: "negado" },
        }),
      })
    );

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.erro).toBeTruthy();
  });

  it("avaliação cortada sem linha no banco também é fail-closed", async () => {
    const resultado = await lerAvaliacaoParaTela(
      {
        organizationId: ORG,
        evaluationId: UUID_CORTADO,
        registroCutover: registroComEvidencia(),
      },
      deps({
        painelParticipante: async () => ({
          ok: false,
          error: { code: "NOT_FOUND", message: "não encontrada" },
        }),
      })
    );

    expect(resultado.ok).toBe(false);
  });

  it("sem caminho soberano configurado, avaliação cortada é recusada", async () => {
    const resultado = await lerAvaliacaoParaTela(
      {
        organizationId: ORG,
        evaluationId: UUID_CORTADO,
        registroCutover: registroComEvidencia(),
      },
      { criarCutover: () => null }
    );

    expect(resultado.ok).toBe(false);
    if (resultado.ok) return;
    expect(resultado.erro).toContain("PostgreSQL");
  });

  it("7) nenhum caminho destes grava no acervo legado", async () => {
    const antes = localStorage.getItem(CHAVE_LEGADO);

    await lerAvaliacaoParaTela(
      { organizationId: ORG, evaluationId: "avaliacao-legada" },
      deps()
    );
    await lerAvaliacaoParaTela(
      { organizationId: ORG, evaluationId: UUID_LEGADO },
      deps()
    );
    await lerAvaliacaoParaTela(
      {
        organizationId: ORG,
        evaluationId: UUID_CORTADO,
        registroCutover: registroComEvidencia(),
      },
      deps()
    );

    expect(localStorage.getItem(CHAVE_LEGADO)).toBe(antes);
    // E nenhum índice de NAVEGAÇÃO é criado por uma LEITURA.
    expect(localStorage.getItem(CHAVE_CICLO_AVALIACOES)).toBeNull();
  });
});
