import { beforeEach, describe, expect, it, vi } from "vitest";
import { instalarLocalStorageEmMemoria } from "../test/localStorageMock.ts";
import { criarCutoverAvaliacoes } from "./avaliacoesSoberanas/cutoverAvaliacoesService.ts";
import {
  avaliacaoVinculadaAoBanco,
  criarArmazenamentoMemoria,
} from "../infrastructure/supabase/avaliacoes/cutover.ts";
import type {
  PainelParticipante,
  RepositorioAvaliacoes,
} from "../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";

/**
 * F5-06 (Issue #103) — CUTOVER: criação/edição/cancelamento/reabertura de
 * avaliação NOVA passam exclusivamente pelo caminho soberano.
 *
 * Garantias verificadas aqui:
 * - nenhuma escrita em `localStorage`;
 * - erro do backend NÃO cai para o caminho legado (fail-closed);
 * - o alvo de criação vem da resolução ano+ciclo e da ponte matrícula → UUID;
 * - a ocorrência usada para gravar notas é a do PAINEL (server-side), nunca um
 *   `participant_id` escolhido pelo cliente.
 */

const ORG = "11111111-1111-4111-8111-111111111111";
const CICLO = "22222222-2222-4222-8222-222222222222";
const AVALIACAO = "33333333-3333-4333-8333-333333333333";
const AVALIADO = "44444444-4444-4444-8444-444444444444";
const OCORRENCIA = "55555555-5555-4555-8555-555555555555";
const SUB = "66666666-6666-4666-8666-666666666666";
const CRITERIO = "88888888-8888-4888-8888-888888888888";

const CHAVE_LEGADO = "feedback-control-feedbacks";

function painel(parcial: Partial<PainelParticipante> = {}): PainelParticipante {
  return {
    evaluationId: AVALIACAO,
    organizationId: ORG,
    cycleId: CICLO,
    cycleAno: 2026,
    cycleNumero: 1,
    configVersionId: "77777777-7777-4777-8777-777777777777",
    status: "RASCUNHO",
    evaluatedCollaboratorId: AVALIADO,
    meusPapeis: ["GESTAO_CADEIA"],
    participanteOcorrenciaId: OCORRENCIA,
    participanteRoleType: "GESTAO_CADEIA",
    participanteVigencia: { validFrom: "2025-01-01T00:00:00Z", validTo: null },
    criterios: [{ criterionId: CRITERIO, code: "c1", name: "Criterio", position: 0 }],
    subcriterios: [
      {
        subcriterionId: SUB,
        code: "s1",
        name: "Sub",
        position: 0,
        criterionCode: "c1",
      },
    ],
    minhasNotas: [{ subcriterionId: SUB, nota: 4 }],
    meusComentarios: [],
    papeisComFeedbackFinal: ["GESTAO_CADEIA"],
    ...parcial,
  };
}

type RepositorioComEspiao = RepositorioAvaliacoes & { readonly chamadas: string[] };

function repositorioFalso(
  comportamentos: Partial<RepositorioAvaliacoes> = {}
): RepositorioComEspiao {
  const chamadas: string[] = [];

  const base: RepositorioAvaliacoes = {
    criar: async () => ({ ok: true, data: AVALIACAO }),
    ler: async () => ({ ok: true, data: null }),
    gravarNotas: async () => ({ ok: true, data: 3.5 }),
    gravarComentario: async () => ({ ok: true, data: null }),
    concluir: async () => ({ ok: true, data: null }),
    reabrir: async () => ({ ok: true, data: null }),
    cancelar: async () => ({ ok: true, data: null }),
    realinharParticipantes: async () => ({ ok: true, data: 0 }),
    transparenciaDoAvaliado: async () =>
      ({
        ok: true,
        data: {
          evaluationId: AVALIACAO,
          notaMedia: null,
          faixa: null,
          criterios: [],
          subcriterios: [],
          colegiado: [],
          comentariosFinais: [],
        },
      }),
    painelParticipante: async () => ({ ok: true, data: painel() }),
    resolverCiclo: async () => ({ ok: true, data: CICLO }),
  };

  // Comportamentos sobrescritos continuam registrando a chamada: é o registro
  // que prova a ORDEM e a ausência de persistência legada.
  const instrumentado = Object.fromEntries(
    Object.entries({ ...base, ...comportamentos }).map(([nome, fn]) => [
      nome,
      async (...args: unknown[]) => {
        chamadas.push(nome);
        return (fn as (...a: unknown[]) => unknown)(...args);
      },
    ])
  ) as unknown as RepositorioAvaliacoes;

  return Object.assign(instrumentado, { chamadas }) as RepositorioComEspiao;
}

describe("cutover: criação, edição e encerramento soberanos", () => {
  beforeEach(() => {
    instalarLocalStorageEmMemoria();
  });

  it("criação resolve ano+ciclo e matrícula e NUNCA escreve no localStorage", async () => {
    const envios: unknown[] = [];
    const repositorio = repositorioFalso({
      criar: async (entrada) => {
        envios.push(entrada);
        return { ok: true, data: AVALIACAO };
      },
    });
    const cutover = criarCutoverAvaliacoes({
      repositorio,
      armazenamento: criarArmazenamentoMemoria(),
    });

    const resultado = await cutover.criarNova({
      organizationId: ORG,
      ano: 2026,
      ciclo: 1,
      matriculaAvaliado: 101,
    });

    expect(resultado.ok).toBe(true);
    expect(resultado.data?.evaluationId).toBe(AVALIACAO);
    expect(resultado.data?.cutoverRegistrado).toBe(true);
    // Ordem: resolve o ciclo ANTES de criar.
    expect(repositorio.chamadas).toEqual(["resolverCiclo", "criar"]);
    // O cliente NÃO apresenta alvo autorizável: a identidade do avaliado é
    // derivada server-side da matrícula (ponte F3-01), e o UUID do CICLO não é
    // reutilizado como se fosse o do colaborador.
    expect(envios).toEqual([
      expect.objectContaining({ cycleId: CICLO, matriculaAvaliado: 101 }),
    ]);
    expect(envios[0]).not.toHaveProperty("evaluatedCollaboratorId");
    // Nenhuma avaliação foi persistida no legado.
    expect(localStorage.getItem(CHAVE_LEGADO)).toBeNull();
  });

  it("erro do backend NÃO cai para o caminho legado (fail-closed)", async () => {
    const repositorio = repositorioFalso({
      resolverCiclo: async () => ({
        ok: false,
        error: { code: "FORBIDDEN", message: "negado" },
      }),
    });
    const cutover = criarCutoverAvaliacoes({ repositorio });

    const resultado = await cutover.criarNova({
      organizationId: ORG,
      ano: 2026,
      ciclo: 1,
      matriculaAvaliado: 101,
    });

    expect(resultado.ok).toBe(false);
    expect(resultado.erro).toBeTruthy();
    expect(repositorio.chamadas).toEqual(["resolverCiclo"]);
    expect(localStorage.getItem(CHAVE_LEGADO)).toBeNull();
  });

  it("ciclo não resolvido (UUID ausente) interrompe antes de criar", async () => {
    const repositorio = repositorioFalso({
      resolverCiclo: async () => ({ ok: true, data: "nao-e-uuid" }),
    });
    const cutover = criarCutoverAvaliacoes({ repositorio });

    const resultado = await cutover.criarNova({
      organizationId: ORG,
      ano: 2026,
      ciclo: 1,
      matriculaAvaliado: 101,
    });

    expect(resultado.ok).toBe(false);
    expect(repositorio.chamadas).toEqual(["resolverCiclo"]);
  });

  it("carrega o painel da PRÓPRIA ocorrência e não pede nada de terceiros", async () => {
    const repositorio = repositorioFalso();
    const cutover = criarCutoverAvaliacoes({ repositorio });

    const resultado = await cutover.carregarPainel({
      organizationId: ORG,
      evaluationId: AVALIACAO,
    });

    expect(resultado.ok).toBe(true);
    expect(resultado.data?.participanteOcorrenciaId).toBe(OCORRENCIA);
    expect(resultado.data?.meusPapeis).toEqual(["GESTAO_CADEIA"]);
    // O painel não traz votos de terceiros por construção (shape do contrato).
    expect(JSON.stringify(resultado.data)).not.toContain("voto");
  });

  it("grava notas usando SEMPRE a ocorrência resolvida no painel", async () => {
    const registros: unknown[] = [];
    const repositorio = repositorioFalso({
      gravarNotas: async (entrada) => {
        registros.push(entrada);
        return { ok: true, data: 3.5 };
      },
    });
    const cutover = criarCutoverAvaliacoes({ repositorio });
    const painelCarregado = painel();

    // A tela informa o NOME do subcritério; o id do catálogo CONGELADO vem do
    // painel (server-side) e nunca é inventado no cliente.
    const resultado = await cutover.gravarNotasDoPainel({
      organizationId: ORG,
      evaluationId: AVALIACAO,
      painel: painelCarregado,
      notas: [{ subcriterio: "Sub", nota: 5 }],
    });

    expect(resultado.ok).toBe(true);
    expect(registros).toEqual([
      expect.objectContaining({
        participantId: OCORRENCIA,
        notas: [{ subcriterion_id: SUB, nota: 5 }],
      }),
    ]);
    // A ocorrência do painel é a única fonte possível de participant_id.
    expect(painelCarregado.participanteOcorrenciaId).toBe(OCORRENCIA);
  });

  it("subcritério fora da configuração congela o lote (fail-closed)", async () => {
    const repositorio = repositorioFalso();
    const cutover = criarCutoverAvaliacoes({ repositorio });

    const resultado = await cutover.gravarNotasDoPainel({
      organizationId: ORG,
      evaluationId: AVALIACAO,
      painel: painel(),
      notas: [{ subcriterio: "Subcritério inexistente", nota: 5 }],
    });

    expect(resultado.ok).toBe(false);
    expect(repositorio.chamadas).not.toContain("gravarNotas");
  });

  it("grava observações de critério pelo CODE do catálogo congelado", async () => {
    const registros: unknown[] = [];
    const repositorio = repositorioFalso({
      gravarComentario: async (entrada) => {
        registros.push(entrada);
        return { ok: true, data: null };
      },
    });
    const cutover = criarCutoverAvaliacoes({ repositorio });

    const resultado = await cutover.gravarObservacoesDoPainel({
      organizationId: ORG,
      evaluationId: AVALIACAO,
      painel: painel(),
      observacoes: [
        { criterioCode: "c1", texto: "Observação do papel" },
        { criterioCode: "c1", texto: "   " },
      ],
    });

    expect(resultado.ok).toBe(true);
    // Observação em branco não vira comentário vazio no banco.
    expect(registros).toEqual([
      expect.objectContaining({
        participantId: OCORRENCIA,
        escopo: "CRITERIO",
        criterionId: CRITERIO,
        texto: "Observação do papel",
      }),
    ]);
  });

  it("comentário final vazio não gera chamada ao servidor", async () => {
    const repositorio = repositorioFalso();
    const cutover = criarCutoverAvaliacoes({ repositorio });

    const resultado = await cutover.gravarComentarioFinalDoPainel({
      organizationId: ORG,
      evaluationId: AVALIACAO,
      painel: painel(),
      texto: "   ",
    });

    expect(resultado.ok).toBe(true);
    expect(repositorio.chamadas).not.toContain("gravarComentario");
  });

  it("painel sem ocorrência resolvida ⇒ recusa fail-closed (nada gravado)", async () => {
    const repositorio = repositorioFalso();
    const cutover = criarCutoverAvaliacoes({ repositorio });
    const gravouAntes = vi.fn();
    expect(gravouAntes).not.toHaveBeenCalled();

    const resultado = await cutover.gravarNotasDoPainel({
      organizationId: ORG,
      evaluationId: AVALIACAO,
      painel: painel({ participanteOcorrenciaId: "" }),
      notas: [{ subcriterio: "Sub", nota: 5 }],
    });

    expect(resultado.ok).toBe(false);
    expect(repositorio.chamadas).not.toContain("gravarNotas");
  });

  it("cancelamento e reabertura usam o caminho soberano com motivo", async () => {
    const repositorio = repositorioFalso();
    const cutover = criarCutoverAvaliacoes({ repositorio });

    const cancelou = await cutover.cancelar({
      organizationId: ORG,
      evaluationId: AVALIACAO,
      motivo: "Desligamento",
    });
    const reabriu = await cutover.reabrir({
      organizationId: ORG,
      evaluationId: AVALIACAO,
      motivo: "Erro de nota",
    });

    expect(cancelou.ok).toBe(true);
    expect(reabriu.ok).toBe(true);
    expect(repositorio.chamadas).toEqual(["cancelar", "reabrir"]);
    expect(localStorage.getItem(CHAVE_LEGADO)).toBeNull();
  });

  it("conclusão é delegada ao servidor (sem cálculo de média no cliente)", async () => {
    const repositorio = repositorioFalso();
    const cutover = criarCutoverAvaliacoes({ repositorio });

    const resultado = await cutover.concluir({ organizationId: ORG, evaluationId: AVALIACAO });

    expect(resultado.ok).toBe(true);
    expect(repositorio.chamadas).toEqual(["concluir"]);
  });

  it("a marca de cutover fica registrada após a criação confirmada", async () => {
    const armazenamento = criarArmazenamentoMemoria();
    const cutover = criarCutoverAvaliacoes({ repositorio: repositorioFalso(), armazenamento });

    await cutover.criarNova({
      organizationId: ORG,
      ano: 2026,
      ciclo: 1,
      matriculaAvaliado: 101,
    });

    expect(avaliacaoVinculadaAoBanco(AVALIACAO, armazenamento)).toBe(true);
  });
});
