/**
 * F5-06 (Issue #103) — REPOSITÓRIO do caminho novo de avaliações.
 *
 * Fronteira única entre a aplicação (services/hooks) e o back-end soberano:
 *
 *   UI/hook → service → REPOSITÓRIO → Edge Function (fronteira confiável)
 *           → ActorContext + ResourceContext + Policy Engine → RPC PostgreSQL
 *
 * Regras preservadas:
 * - NENHUMA regra de autorização aqui: o cliente só envia INTENÇÃO e traduz o
 *   código público de erro. Quem decide ALLOW/DENY é o Policy Engine, server-side;
 * - NENHUM cálculo oficial aqui: `nota_media`/agregados vêm materializados do
 *   banco (D13) — o TypeScript não é fonte de verdade do cálculo;
 * - identidade por UUID (`collaborators.id`), nunca matrícula;
 * - `localStorage` não participa deste caminho (sem dual-write, D12).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CAPABILITY_POR_OPERACAO,
  ehUuid,
  type AlvoAvaliacao,
  type CodigoPublico,
  type OperacaoAvaliacao,
} from "./contrato.ts";

export const FUNCAO_AVALIACOES = "avaliacoes";

/** Estado REAL da avaliação (projeção de leitura do caminho novo). */
export interface AvaliacaoSoberana {
  readonly id: string;
  readonly organizationId: string;
  readonly cycleId: string;
  readonly evaluatedCollaboratorId: string;
  readonly status: string;
  readonly notaMedia: number | null;
  readonly dataConclusao: string | null;
  readonly encerradaComPendencias: boolean;
}

/** Projeção de TRANSPARÊNCIA do avaliado (D20): nunca voto/nota individual. */
export interface TransparenciaAvaliado {
  readonly evaluationId: string;
  readonly notaMedia: number | null;
  readonly faixa: {
    readonly nota: number;
    readonly significado: string;
    readonly descricao: string;
    readonly limiteMinimo: number;
  } | null;
  readonly criterios: readonly { readonly criterio: string; readonly nota: number }[];
  readonly subcriterios: readonly {
    readonly criterio: string;
    readonly subcriterio: string;
    readonly nota: number;
  }[];
  readonly colegiado: readonly { readonly colaborador: string }[];
  readonly comentariosFinais: readonly { readonly roleType: string; readonly texto: string }[];
}

export interface ErroRepositorioAvaliacoes {
  readonly code: CodigoPublico;
  readonly message: string;
}

export type ResultadoRepositorio<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: ErroRepositorioAvaliacoes };

export interface EntradaCriarAvaliacao {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly evaluatedCollaboratorId: string;
  /**
   * Matrícula do avaliado (INTENÇÃO da tela): a fronteira confiável resolve a
   * ponte para o UUID (F3-01) e é ele que prevalece na criação.
   */
  readonly matriculaAvaliado?: number | string | null;
}

/** Projeção de EDIÇÃO: SOMENTE a ocorrência do próprio ator (decisão 1). */
export interface PainelParticipante {
  readonly evaluationId: string;
  readonly organizationId: string;
  readonly cycleId: string;
  readonly configVersionId: string;
  readonly status: string;
  readonly evaluatedCollaboratorId: string;
  /** Papéis atribuídos ao PRÓPRIO ator (nenhum papel de terceiros). */
  readonly meusPapeis: readonly string[];
  readonly participanteOcorrenciaId: string;
  readonly participanteRoleType: string;
  readonly participanteVigencia: {
    readonly validFrom: string;
    readonly validTo: string | null;
  };
  readonly criterios: readonly {
    readonly code: string;
    readonly name: string;
    readonly position: number;
  }[];
  readonly subcriterios: readonly {
    readonly code: string;
    readonly name: string;
    readonly position: number;
    readonly criterionCode: string;
  }[];
  /** Notas da PRÓPRIA ocorrência (nunca de terceiros). */
  readonly minhasNotas: readonly {
    readonly subcriterionId: string;
    readonly nota: number;
  }[];
  readonly meusComentarios: readonly {
    readonly escopo: string;
    readonly criterionId: string | null;
    readonly texto: string;
  }[];
  readonly papeisComFeedbackFinal: readonly string[];
}

export interface EntradaGravarNotas {
  readonly organizationId: string;
  readonly evaluationId: string;
  readonly participantId: string;
  readonly notas: readonly { readonly subcriterion_id: string; readonly nota: number }[];
}

export interface EntradaGravarComentario {
  readonly organizationId: string;
  readonly evaluationId: string;
  readonly participantId: string;
  readonly escopo: "CRITERIO" | "FINAL";
  readonly criterionId?: string | null;
  readonly texto: string;
}

export interface EntradaOperacaoAuditada {
  readonly organizationId: string;
  readonly evaluationId: string;
  /** Obrigatório em reabertura/cancelamento; a conclusão não exige motivo. */
  readonly motivo?: string;
}

export interface RepositorioAvaliacoes {
  criar(entrada: EntradaCriarAvaliacao): Promise<ResultadoRepositorio<string>>;
  ler(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
  }): Promise<ResultadoRepositorio<AvaliacaoSoberana | null>>;
  gravarNotas(entrada: EntradaGravarNotas): Promise<ResultadoRepositorio<number | null>>;
  gravarComentario(entrada: EntradaGravarComentario): Promise<ResultadoRepositorio<null>>;
  concluir(entrada: EntradaOperacaoAuditada): Promise<ResultadoRepositorio<null>>;
  reabrir(entrada: EntradaOperacaoAuditada): Promise<ResultadoRepositorio<null>>;
  cancelar(entrada: EntradaOperacaoAuditada): Promise<ResultadoRepositorio<null>>;
  realinharParticipantes(entrada: EntradaOperacaoAuditada): Promise<ResultadoRepositorio<number>>;
  transparenciaDoAvaliado(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
  }): Promise<ResultadoRepositorio<TransparenciaAvaliado>>;
  /** Painel de EDIÇÃO da própria ocorrência (decisão 1). */
  painelParticipante(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
  }): Promise<ResultadoRepositorio<PainelParticipante>>;
  /**
   * Resolve ano+ciclo (INTENÇÃO) para o UUID soberano do ciclo, dentro do
   * tenant validado. A matrícula do avaliado acompanha a intenção para que o
   * Edge resolva o ALVO autorizável (ponte F3-01) antes do Policy Engine.
   */
  resolverCiclo(entrada: {
    readonly organizationId: string;
    readonly ano: number;
    readonly numero: number;
    readonly matriculaAvaliado: number | string;
  }): Promise<ResultadoRepositorio<string>>;
}

// ---------------------------------------------------------------------------
// Adapter Supabase (Edge Function `avaliacoes`)
// ---------------------------------------------------------------------------

interface RespostaEdge {
  ok?: unknown;
  resultado?: unknown;
  error?: { code?: unknown; message?: unknown };
}

function codigoPublico(valor: unknown): CodigoPublico {
  switch (valor) {
    case "FORBIDDEN":
    case "NOT_FOUND":
    case "CONFLICT":
    case "INVALID_INPUT":
    case "INTERNAL":
    case "NOT_AUTHORIZED":
      return valor;
    default:
      return "INTERNAL";
  }
}

function montarCorpo(
  operacao: OperacaoAvaliacao,
  organizationId: string,
  alvo: AlvoAvaliacao,
  extras: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    organization_id: organizationId,
    operacao,
    alvo,
    ...extras,
  };
}

export function criarRepositorioAvaliacoesSupabase(
  cliente: SupabaseClient
): RepositorioAvaliacoes {
  async function invocar<T>(
    corpo: Record<string, unknown>,
    projetar: (resultado: unknown) => T
  ): Promise<ResultadoRepositorio<T>> {
    const { data, error } = await cliente.functions.invoke<RespostaEdge>(FUNCAO_AVALIACOES, {
      body: corpo,
    });

    if (error) {
      // A Edge devolve `{ error: { code, message } }`; o cliente supabase-js
      // expõe o corpo em `error.context` quando o status não é 2xx.
      const contexto = (error as { context?: { error?: { code?: unknown; message?: unknown } } })
        .context;
      return {
        ok: false,
        error: {
          code: codigoPublico(contexto?.error?.code),
          message:
            typeof contexto?.error?.message === "string"
              ? contexto.error.message
              : "Operação de avaliação recusada.",
        },
      };
    }

    if (data?.error) {
      return {
        ok: false,
        error: {
          code: codigoPublico(data.error.code),
          message:
            typeof data.error.message === "string"
              ? data.error.message
              : "Operação de avaliação recusada.",
        },
      };
    }

    try {
      return { ok: true, data: projetar(data?.resultado ?? null) };
    } catch {
      return {
        ok: false,
        error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
      };
    }
  }

  return {
    criar: (entrada) =>
      invocar(
        montarCorpo(
          "evaluation.criar",
          entrada.organizationId,
          {
            type: "collaborator",
            id: entrada.evaluatedCollaboratorId,
          },
          {
            cycle_id: entrada.cycleId,
            ...(entrada.matriculaAvaliado === undefined ||
            entrada.matriculaAvaliado === null
              ? {}
              : { matricula_avaliado: entrada.matriculaAvaliado }),
          }
        ),
        (resultado) => {
          if (typeof resultado !== "string" || !ehUuid(resultado)) {
            throw new Error("id de avaliação ausente");
          }
          return resultado;
        }
      ),

    ler: (entrada) =>
      invocar(
        montarCorpo("evaluation.ler", entrada.organizationId, {
          type: "evaluation",
          id: entrada.evaluationId,
        }),
        (resultado) => {
          if (resultado === null || resultado === undefined) return null;
          return projetarAvaliacao(resultado);
        }
      ),

    gravarNotas: (entrada) =>
      invocar(
        montarCorpo(
          "evaluation.gravar_notas",
          entrada.organizationId,
          { type: "evaluation", id: entrada.evaluationId },
          { participant_id: entrada.participantId, notas: entrada.notas }
        ),
        (resultado) => (typeof resultado === "number" ? resultado : Number(resultado))
      ),

    gravarComentario: (entrada) =>
      invocar(
        montarCorpo(
          "evaluation.gravar_comentario",
          entrada.organizationId,
          { type: "evaluation", id: entrada.evaluationId },
          {
            participant_id: entrada.participantId,
            escopo: entrada.escopo,
            criterion_id: entrada.criterionId ?? null,
            texto: entrada.texto,
          }
        ),
        () => null
      ),

    concluir: (entrada) =>
      invocar(
        montarCorpo("evaluation.concluir", entrada.organizationId, {
          type: "evaluation",
          id: entrada.evaluationId,
        }),
        () => null
      ),

    reabrir: (entrada) =>
      invocar(
        montarCorpo(
          "evaluation.reabrir",
          entrada.organizationId,
          { type: "evaluation", id: entrada.evaluationId },
          { motivo: entrada.motivo }
        ),
        () => null
      ),

    cancelar: (entrada) =>
      invocar(
        montarCorpo(
          "evaluation.cancelar",
          entrada.organizationId,
          { type: "evaluation", id: entrada.evaluationId },
          { motivo: entrada.motivo }
        ),
        () => null
      ),

    realinharParticipantes: (entrada) =>
      invocar(
        montarCorpo(
          "evaluation.participantes_realinhar",
          entrada.organizationId,
          { type: "evaluation", id: entrada.evaluationId },
          { motivo: entrada.motivo }
        ),
        (resultado) => (typeof resultado === "number" ? resultado : Number(resultado))
      ),

    transparenciaDoAvaliado: (entrada) =>
      invocar(
        montarCorpo("evaluation.transparencia", entrada.organizationId, {
          type: "evaluation",
          id: entrada.evaluationId,
        }),
        (resultado) => projetarTransparencia(resultado)
      ),

    painelParticipante: (entrada) =>
      invocar(
        montarCorpo("evaluation.painel_participante", entrada.organizationId, {
          type: "evaluation",
          id: entrada.evaluationId,
        }),
        (resultado) => projetarPainel(resultado)
      ),

    resolverCiclo: (entrada) =>
      invocar(
        montarCorpo(
          "evaluation.resolver_ciclo",
          entrada.organizationId,
          // Alvo temporário: o Edge o SUBSTITUI pelo UUID do colaborador
          // resolvido a partir da matrícula (ponte F3-01) ANTES do Policy
          // Engine. O cliente nunca fornece o alvo autorizável.
          { type: "collaborator", id: "00000000-0000-0000-0000-000000000000" },
          {
            ano: entrada.ano,
            numero: entrada.numero,
            matricula_avaliado: entrada.matriculaAvaliado,
          }
        ),
        (resultado) => projetarCicloResolvido(resultado)
      ),
  };
}

function projetarCicloResolvido(valor: unknown): string {
  if (typeof valor === "string") return valor;
  const registro = comoRegistro(valor ?? {});
  return String(registro.cycle_id ?? "");
}

function projetarPainel(valor: unknown): PainelParticipante {
  const registro = comoRegistro(valor);
  const vigencia = (registro.participante_vigencia ?? {}) as Record<string, unknown>;
  const lista = <T>(chave: string, mapear: (item: Record<string, unknown>) => T): T[] =>
    Array.isArray(registro[chave])
      ? (registro[chave] as Record<string, unknown>[]).map(mapear)
      : [];

  return {
    evaluationId: String(registro.evaluation_id),
    organizationId: String(registro.organization_id),
    cycleId: String(registro.cycle_id),
    configVersionId: String(registro.config_version_id),
    status: String(registro.status),
    evaluatedCollaboratorId: String(registro.evaluated_collaborator_id),
    meusPapeis: Array.isArray(registro.meus_papeis)
      ? (registro.meus_papeis as unknown[]).map(String)
      : [],
    participanteOcorrenciaId: String(registro.participante_ocorrencia_id),
    participanteRoleType: String(registro.participante_role_type),
    participanteVigencia: {
      validFrom: String(vigencia.valid_from ?? ""),
      validTo: typeof vigencia.valid_to === "string" ? vigencia.valid_to : null,
    },
    criterios: lista("criterios", (item) => ({
      code: String(item.code),
      name: String(item.name),
      position: Number(item.position),
    })),
    subcriterios: lista("subcriterios", (item) => ({
      code: String(item.code),
      name: String(item.name),
      position: Number(item.position),
      criterionCode: String(item.criterion_code),
    })),
    minhasNotas: lista("minhas_notas", (item) => ({
      subcriterionId: String(item.subcriterion_id),
      nota: Number(item.nota),
    })),
    meusComentarios: lista("meus_comentarios", (item) => ({
      escopo: String(item.escopo),
      criterionId: item.criterion_id === null ? null : String(item.criterion_id),
      texto: String(item.texto),
    })),
    papeisComFeedbackFinal: Array.isArray(registro.papeis_com_feedback_final)
      ? (registro.papeis_com_feedback_final as unknown[]).map(String)
      : [],
  };
}

function comoRegistro(valor: unknown): Record<string, unknown> {
  if (typeof valor !== "object" || valor === null || Array.isArray(valor)) {
    throw new Error("Resposta inesperada do servidor.");
  }
  return valor as Record<string, unknown>;
}

function projetarAvaliacao(valor: unknown): AvaliacaoSoberana {
  const registro = comoRegistro(valor);
  return {
    id: String(registro.id),
    organizationId: String(registro.organization_id),
    cycleId: String(registro.cycle_id),
    evaluatedCollaboratorId: String(registro.evaluated_collaborator_id),
    status: String(registro.status),
    notaMedia:
      registro.nota_media === null || registro.nota_media === undefined
        ? null
        : Number(registro.nota_media),
    dataConclusao:
      typeof registro.data_conclusao === "string" ? registro.data_conclusao : null,
    encerradaComPendencias: registro.encerrada_com_pendencias === true,
  };
}

function projetarTransparencia(valor: unknown): TransparenciaAvaliado {
  const registro = comoRegistro(valor);
  const faixa = registro.faixa;
  return {
    evaluationId: String(registro.evaluation_id),
    notaMedia:
      registro.nota_media === null || registro.nota_media === undefined
        ? null
        : Number(registro.nota_media),
    faixa:
      typeof faixa === "object" && faixa !== null
        ? {
            nota: Number((faixa as Record<string, unknown>).nota),
            significado: String((faixa as Record<string, unknown>).significado),
            descricao: String((faixa as Record<string, unknown>).descricao),
            limiteMinimo: Number((faixa as Record<string, unknown>).limite_minimo),
          }
        : null,
    criterios: Array.isArray(registro.criterios)
      ? (registro.criterios as Record<string, unknown>[]).map((item) => ({
          criterio: String(item.criterio),
          nota: Number(item.nota),
        }))
      : [],
    subcriterios: Array.isArray(registro.subcriterios)
      ? (registro.subcriterios as Record<string, unknown>[]).map((item) => ({
          criterio: String(item.criterio),
          subcriterio: String(item.subcriterio),
          nota: Number(item.nota),
        }))
      : [],
    colegiado: Array.isArray(registro.colegiado)
      ? (registro.colegiado as Record<string, unknown>[]).map((item) => ({
          colaborador: String(item.colaborador),
        }))
      : [],
    comentariosFinais: Array.isArray(registro.comentarios_finais)
      ? (registro.comentarios_finais as Record<string, unknown>[]).map((item) => ({
          roleType: String(item.role_type),
          texto: String(item.texto),
        }))
      : [],
  };
}

/** Capacidade exigida por operação — exposto para testes de vínculo contrato×operação. */
export { CAPABILITY_POR_OPERACAO };
