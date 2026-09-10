import { describe, expect, it } from "vitest";
import {
  criarRepositorioAvaliacoesSupabase,
  FUNCAO_AVALIACOES,
} from "./repositorioAvaliacoes.ts";
import {
  INSTANTE_CUTOVER_AVALIACOES,
  origemDoRegistroLegado,
  separarAcervoLegado,
} from "./cutover.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

const ORG = "11111111-1111-4111-8111-111111111111";
const AVALIACAO = "22222222-2222-4222-8222-222222222222";
const COLABORADOR = "33333333-3333-4333-8333-333333333333";
const PARTICIPANTE = "44444444-4444-4444-8444-444444444444";
const CICLO = "55555555-5555-4555-8555-555555555555";
const SUB = "66666666-6666-4666-8666-666666666666";

interface Invocacao {
  readonly nome: string;
  readonly body: Record<string, unknown>;
}

function clienteFalso(resposta: {
  readonly data?: unknown;
  readonly error?: unknown;
}): { readonly cliente: SupabaseClient; readonly invocacoes: Invocacao[] } {
  const invocacoes: Invocacao[] = [];
  const cliente = {
    functions: {
      invoke: async (nome: string, opcoes: { body: Record<string, unknown> }) => {
        invocacoes.push({ nome, body: opcoes.body });
        return { data: resposta.data ?? null, error: resposta.error ?? null };
      },
    },
  } as unknown as SupabaseClient;
  return { cliente, invocacoes };
}

describe("repositório de avaliações (caminho novo)", () => {
  it("cria avaliação enviando apenas a INTENÇÃO (sem actor, sem config_version, sem participantes)", async () => {
    const { cliente, invocacoes } = clienteFalso({ data: { ok: true, resultado: AVALIACAO } });
    const repo = criarRepositorioAvaliacoesSupabase(cliente);

    const resultado = await repo.criar({
      organizationId: ORG,
      cycleId: CICLO,
      evaluatedCollaboratorId: COLABORADOR,
    });

    expect(resultado).toEqual({ ok: true, data: AVALIACAO });
    const envio = invocacoes[0]!;
    expect(envio.nome).toBe(FUNCAO_AVALIACOES);
    expect(envio.body).toEqual({
      organization_id: ORG,
      operacao: "evaluation.criar",
      alvo: { type: "collaborator", id: COLABORADOR },
      cycle_id: CICLO,
    });
    // Nenhuma autoridade no payload: o snapshot de participantes e a versão de
    // configuração são derivados server-side (D6/D16/D23).
    for (const proibido of [
      "actor_id",
      "actor_user_profile_id",
      "participants",
      "config_version_id",
      "organizationId",
      "nota",
      "notaMedia",
    ]) {
      expect(Object.keys(envio.body)).not.toContain(proibido);
    }
  });

  it("grava notas com participant_id e notas (o cálculo oficial fica no servidor)", async () => {
    const { cliente, invocacoes } = clienteFalso({ data: { ok: true, resultado: 3.5 } });
    const repo = criarRepositorioAvaliacoesSupabase(cliente);

    const resultado = await repo.gravarNotas({
      organizationId: ORG,
      evaluationId: AVALIACAO,
      participantId: PARTICIPANTE,
      notas: [{ subcriterion_id: SUB, nota: 4 }],
    });

    expect(resultado).toEqual({ ok: true, data: 3.5 });
    expect(invocacoes[0]!.body).toMatchObject({
      operacao: "evaluation.gravar_notas",
      participant_id: PARTICIPANTE,
      notas: [{ subcriterion_id: SUB, nota: 4 }],
    });
    expect(Object.keys(invocacoes[0]!.body)).not.toContain("nota_media");
  });

  it("conclusão/reabertura/cancelamento enviam motivo quando exigido", async () => {
    const { cliente, invocacoes } = clienteFalso({ data: { ok: true } });
    const repo = criarRepositorioAvaliacoesSupabase(cliente);

    await repo.concluir({ organizationId: ORG, evaluationId: AVALIACAO, motivo: "irrelevante" });
    await repo.reabrir({ organizationId: ORG, evaluationId: AVALIACAO, motivo: "erro de nota" });
    await repo.cancelar({ organizationId: ORG, evaluationId: AVALIACAO, motivo: "desligamento" });

    expect(invocacoes.map((i) => i.body.operacao)).toEqual([
      "evaluation.concluir",
      "evaluation.reabrir",
      "evaluation.cancelar",
    ]);
    expect(invocacoes[1]!.body.motivo).toBe("erro de nota");
    expect(invocacoes[2]!.body.motivo).toBe("desligamento");
  });

  it("DENY do servidor vira erro público, sem lançar exceção", async () => {
    const { cliente } = clienteFalso({
      data: { error: { code: "FORBIDDEN", message: "Operação negada." } },
    });
    const repo = criarRepositorioAvaliacoesSupabase(cliente);

    const resultado = await repo.concluir({
      organizationId: ORG,
      evaluationId: AVALIACAO,
      motivo: "irrelevante",
    });

    expect(resultado.ok).toBe(false);
    if (!resultado.ok) {
      expect(resultado.error.code).toBe("FORBIDDEN");
    }
  });

  it("erro HTTP da Edge (não-2xx) é traduzido pelo contexto", async () => {
    const { cliente } = clienteFalso({
      error: { message: "Edge Function returned a non-2xx status code", context: { error: { code: "NOT_FOUND" } } },
    });
    const repo = criarRepositorioAvaliacoesSupabase(cliente);

    const resultado = await repo.ler({ organizationId: ORG, evaluationId: AVALIACAO });
    expect(resultado.ok).toBe(false);
    if (!resultado.ok) expect(resultado.error.code).toBe("NOT_FOUND");
  });

  it("código desconhecido colapsa em INTERNAL (não vaza razão interna)", async () => {
    const { cliente } = clienteFalso({ data: { error: { code: "P0001" } } });
    const repo = criarRepositorioAvaliacoesSupabase(cliente);
    const resultado = await repo.ler({ organizationId: ORG, evaluationId: AVALIACAO });
    expect(resultado.ok).toBe(false);
    if (!resultado.ok) expect(resultado.error.code).toBe("INTERNAL");
  });

  it("leitura projeta o estado real da avaliação", async () => {
    const { cliente } = clienteFalso({
      data: {
        ok: true,
        resultado: {
          id: AVALIACAO,
          organization_id: ORG,
          cycle_id: CICLO,
          evaluated_collaborator_id: COLABORADOR,
          status: "CONCLUIDA",
          nota_media: "3.50000000",
          data_conclusao: "2026-02-01T10:00:00Z",
          encerrada_com_pendencias: false,
        },
      },
    });
    const repo = criarRepositorioAvaliacoesSupabase(cliente);

    const resultado = await repo.ler({ organizationId: ORG, evaluationId: AVALIACAO });
    expect(resultado.ok).toBe(true);
    if (resultado.ok) {
      expect(resultado.data?.notaMedia).toBe(3.5);
      expect(resultado.data?.status).toBe("CONCLUIDA");
    }
  });

  it("transparência NUNCA expõe voto/nota individual nem participant_id", async () => {
    const { cliente, invocacoes } = clienteFalso({
      data: {
        ok: true,
        resultado: {
          evaluation_id: AVALIACAO,
          nota_media: 3.5,
          faixa: { nota: 3, significado: "Dentro do esperado", descricao: "...", limite_minimo: 2.9 },
          criterios: [{ criterio: "Comunicacao", nota: 3.5 }],
          subcriterios: [{ criterio: "Comunicacao", subcriterio: "Clareza", nota: 3.5 }],
          colegiado: [{ colaborador: "Membro Sintetico" }],
          comentarios_finais: [{ role_type: "GESTAO_CADEIA", texto: "Feedback final." }],
        },
      },
    });
    const repo = criarRepositorioAvaliacoesSupabase(cliente);

    const resultado = await repo.transparenciaDoAvaliado({
      organizationId: ORG,
      evaluationId: AVALIACAO,
    });

    expect(invocacoes[0]!.body.operacao).toBe("evaluation.transparencia");
    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;
    const serializado = JSON.stringify(resultado.data);
    expect(serializado).not.toContain("participant_id");
    expect(serializado).not.toContain("voto");
    expect(serializado).not.toContain("nota_individual");
    expect(resultado.data.colegiado).toHaveLength(1);
  });
});

describe("cutover do domínio de avaliações (D12/§11)", () => {
  it("classifica registros legados pela data de criação", () => {
    expect(origemDoRegistroLegado({ dataCriacao: "2025-12-31T23:59:59.000Z" })).toBe(
      "LEGADO_LOCAL"
    );
    expect(origemDoRegistroLegado({ dataCriacao: INSTANTE_CUTOVER_AVALIACOES })).toBe("POSTGRES");
    expect(origemDoRegistroLegado({ dataCriacao: "2026-05-01T00:00:00.000Z" })).toBe("POSTGRES");
  });

  it("sem data de criação ⇒ trate como LEGADO (não ingressa no caminho novo por omissão)", () => {
    expect(origemDoRegistroLegado({})).toBe("LEGADO_LOCAL");
    expect(origemDoRegistroLegado({ dataCriacao: "" })).toBe("LEGADO_LOCAL");
    expect(origemDoRegistroLegado({ dataCriacao: "data-invalida" })).toBe("LEGADO_LOCAL");
  });

  it("separa o acervo SEM misturar autoridades (legado somente leitura)", () => {
    const registros = [
      { id: "a", dataCriacao: "2025-06-01T00:00:00.000Z" },
      { id: "b", dataCriacao: "2026-03-01T00:00:00.000Z" },
      { id: "c" },
    ];
    const { legado, aposCorte } = separarAcervoLegado(registros);
    expect(legado.map((r) => r.id)).toEqual(["a", "c"]);
    expect(aposCorte.map((r) => r.id)).toEqual(["b"]);
  });
});
