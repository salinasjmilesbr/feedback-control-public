import { describe, expect, it } from "vitest";
import {
  criarRepositorioAvaliacoesSupabase,
  FUNCAO_AVALIACOES,
} from "./repositorioAvaliacoes.ts";
import {
  avaliacaoVinculadaAoBanco,
  CHAVE_AVALIACOES_CORTADAS,
  criarArmazenamentoMemoria,
  ehIdTecnicoPostgres,
  lerAvaliacoesCortadas,
  origemDoMarcador,
  registrarAvaliacaoCortada,
  separarAcervoLegado,
  type MarcadorOrigem,
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

  it("criação SEM alvo do cliente envia alvo NEUTRO e mantém a matrícula como intenção", async () => {
    const { cliente, invocacoes } = clienteFalso({ data: { ok: true, resultado: AVALIACAO } });
    const repo = criarRepositorioAvaliacoesSupabase(cliente);

    // A tela não conhece (nem deve conhecer) o UUID do colaborador avaliado: a
    // identidade é derivada server-side da matrícula (ponte F3-01). O alvo
    // enviado é NEUTRO e o Edge o substitui ANTES do Policy Engine.
    const resultado = await repo.criar({
      organizationId: ORG,
      cycleId: CICLO,
      matriculaAvaliado: 101,
    });

    expect(resultado).toEqual({ ok: true, data: AVALIACAO });
    const envio = invocacoes[0]!;
    expect(envio.body.alvo).toEqual({
      type: "collaborator",
      id: "00000000-0000-0000-0000-000000000000",
    });
    expect(envio.body.matricula_avaliado).toBe(101);
    expect(envio.body.cycle_id).toBe(CICLO);
    // O uuid do CICLO nunca é reaproveitado como identidade do avaliado.
    expect((envio.body.alvo as { id: string }).id).not.toBe(CICLO);
  });

  it("painel do participante projeta o catálogo congelado e SOMENTE a própria ocorrência", async () => {
    const { cliente } = clienteFalso({
      data: {
        ok: true,
        resultado: {
          evaluation_id: AVALIACAO,
          organization_id: ORG,
          cycle_id: CICLO,
          cycle_ano: 2026,
          cycle_numero: 1,
          config_version_id: "77777777-7777-4777-8777-777777777777",
          status: "RASCUNHO",
          evaluated_collaborator_id: COLABORADOR,
          meus_papeis: ["GESTAO_CADEIA"],
          participante_ocorrencia_id: PARTICIPANTE,
          participante_role_type: "GESTAO_CADEIA",
          participante_vigencia: {
            valid_from: "2026-01-01T00:00:00Z",
            valid_to: null,
          },
          criterios: [{ id: "c-1", code: "c1", name: "Criterio", position: 0 }],
          subcriterios: [
            {
              id: SUB,
              code: "s1",
              name: "Sub",
              position: 0,
              criterion_code: "c1",
            },
          ],
          minhas_notas: [{ subcriterion_id: SUB, nota: 4 }],
          meus_comentarios: [
            { escopo: "FINAL", criterion_id: null, texto: "Meu feedback" },
          ],
          papeis_com_feedback_final: ["GESTAO_CADEIA"],
        },
      },
    });
    const repo = criarRepositorioAvaliacoesSupabase(cliente);

    const resultado = await repo.painelParticipante({
      organizationId: ORG,
      evaluationId: AVALIACAO,
    });

    expect(resultado.ok).toBe(true);
    if (!resultado.ok) return;

    // Ids do catálogo CONGELADO: indispensáveis para gravar sem inventar id.
    expect(resultado.data.criterios[0]?.criterionId).toBe("c-1");
    expect(resultado.data.subcriterios[0]?.subcriterionId).toBe(SUB);
    // Contexto do ciclo vem da linha real do banco.
    expect(resultado.data.cycleAno).toBe(2026);
    expect(resultado.data.cycleNumero).toBe(1);
    // Somente a PRÓPRIA ocorrência: nenhum dado de terceiro.
    expect(resultado.data.participanteOcorrenciaId).toBe(PARTICIPANTE);
    const serializado = JSON.stringify(resultado.data);
    expect(serializado).not.toContain("voto");
    expect(serializado).not.toContain("terceiro");
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
  // ADVERTÊNCIA DA AUDITORIA: a origem NÃO pode ser inferida por DATA. Um
  // registro local criado "depois do cutover" continuaria sendo local; uma data
  // arbitrária no código não é evidência de escrita no PostgreSQL.
  const registrosLocais = [
    { id: "local-2025", dataCriacao: "2025-01-01T00:00:00.000Z" },
    { id: "local-2026", dataCriacao: "2026-12-31T23:59:59.000Z" },
    { id: "local-sem-data" },
    { id: "local-data-invalida", dataCriacao: "data-invalida" },
  ];

  it("NENHUM registro local é classificado como banco apenas pela data", () => {
    const { legado, postgres } = separarAcervoLegado(
      registrosLocais,
      () => ({ origem: "LEGADO_LOCAL" }) as MarcadorOrigem
    );

    expect(postgres).toHaveLength(0);
    expect(legado.map((r) => r.id)).toEqual([
      "local-2025",
      "local-2026",
      "local-sem-data",
      "local-data-invalida",
    ]);
  });

  it("as quatro naturezas de registro local permanecem legado (2025, 2026, sem data, data inválida)", () => {
    for (const registro of registrosLocais) {
      // Sem marcador do caminho novo ⇒ legado, independentemente da data.
      expect(origemDoMarcador(null)).toBe("LEGADO_LOCAL");
      expect(origemDoMarcador({ origem: "LEGADO_LOCAL", evaluationId: registro.id })).toBe(
        "LEGADO_LOCAL"
      );
    }
  });

  it("marcador POSTGRES exige id técnico (UUID) — id local não vira banco", () => {
    expect(origemDoMarcador({ origem: "POSTGRES", evaluationId: AVALIACAO })).toBe("POSTGRES");
    expect(origemDoMarcador({ origem: "POSTGRES", evaluationId: "avaliacao-local-1" })).toBe(
      "LEGADO_LOCAL"
    );
    expect(origemDoMarcador({ origem: "POSTGRES", evaluationId: "" })).toBe("LEGADO_LOCAL");
    expect(ehIdTecnicoPostgres("avaliacao-local-1")).toBe(false);
    expect(ehIdTecnicoPostgres(AVALIACAO)).toBe(true);
  });

  it("avaliação REALMENTE criada no PostgreSQL entra como banco; o resto é legado", () => {
    const armazenamento = criarArmazenamentoMemoria();
    // Escrita server-side confirmada: a RPC devolveu o UUID.
    const marcador = registrarAvaliacaoCortada(AVALIACAO, armazenamento);
    expect(marcador).toEqual({ origem: "POSTGRES", evaluationId: AVALIACAO });

    const registros = [
      ...registrosLocais,
      { id: AVALIACAO, dataCriacao: "2025-01-01T00:00:00.000Z" },
    ];
    const { legado, postgres } = separarAcervoLegado(registros, (registro) => {
      const id = (registro as { id: string }).id;
      return avaliacaoVinculadaAoBanco(id, armazenamento)
        ? { origem: "POSTGRES" as const, evaluationId: id }
        : { origem: "LEGADO_LOCAL" as const, evaluationId: id };
    });

    // Mesmo com data antiga, a evidência estrutural manda: é do banco.
    expect(postgres.map((r) => r.id)).toEqual([AVALIACAO]);
    expect(legado).toHaveLength(registrosLocais.length);
  });

  it("registrar sem id técnico NÃO cria evidência de banco", () => {
    const armazenamento = criarArmazenamentoMemoria();
    const marcador = registrarAvaliacaoCortada("avaliacao-local-1", armazenamento);

    expect(marcador).toEqual({ origem: "LEGADO_LOCAL", evaluationId: null });
    expect(avaliacaoVinculadaAoBanco("avaliacao-local-1", armazenamento)).toBe(false);
    expect(lerAvaliacoesCortadas(armazenamento).size).toBe(0);
  });

  it("registra a avaliação cortada e nunca volta a tratá-la como legado", () => {
    const armazenamento = criarArmazenamentoMemoria();
    expect(avaliacaoVinculadaAoBanco(AVALIACAO, armazenamento)).toBe(false);
    expect(lerAvaliacoesCortadas(armazenamento).size).toBe(0);

    registrarAvaliacaoCortada(AVALIACAO, armazenamento);

    expect(avaliacaoVinculadaAoBanco(AVALIACAO, armazenamento)).toBe(true);
    expect([...lerAvaliacoesCortadas(armazenamento)]).toEqual([AVALIACAO]);
    expect(armazenamento.getItem(CHAVE_AVALIACOES_CORTADAS)).toContain(AVALIACAO);
  });

  it("registrar duas vezes não duplica e id inválido é ignorado (fail-closed)", () => {
    const armazenamento = criarArmazenamentoMemoria();
    registrarAvaliacaoCortada(AVALIACAO, armazenamento);
    registrarAvaliacaoCortada(AVALIACAO, armazenamento);
    registrarAvaliacaoCortada("   ", armazenamento);
    registrarAvaliacaoCortada("nao-e-uuid", armazenamento);

    expect([...lerAvaliacoesCortadas(armazenamento)]).toEqual([AVALIACAO]);
  });

  it("conteúdo corrompido do registro não quebra a leitura nem cria evidência", () => {
    const armazenamento = criarArmazenamentoMemoria();
    armazenamento.setItem(CHAVE_AVALIACOES_CORTADAS, "{nao-e-json");
    expect(lerAvaliacoesCortadas(armazenamento).size).toBe(0);

    armazenamento.setItem(CHAVE_AVALIACOES_CORTADAS, JSON.stringify({ a: 1 }));
    expect(lerAvaliacoesCortadas(armazenamento).size).toBe(0);

    // Id não-técnico gravado por fora não vira evidência de banco.
    armazenamento.setItem(
      CHAVE_AVALIACOES_CORTADAS,
      JSON.stringify(["avaliacao-local-1", AVALIACAO])
    );
    expect([...lerAvaliacoesCortadas(armazenamento)]).toEqual([AVALIACAO]);
  });

  it("sem armazenamento disponível, a marca é inerte (não lança)", () => {
    expect(() => registrarAvaliacaoCortada(AVALIACAO, null)).not.toThrow();
    expect(registrarAvaliacaoCortada(AVALIACAO, null)).toEqual({
      origem: "POSTGRES",
      evaluationId: AVALIACAO,
    });
    expect(lerAvaliacoesCortadas(null).size).toBe(0);
    expect(avaliacaoVinculadaAoBanco(AVALIACAO, null)).toBe(false);
  });
});
