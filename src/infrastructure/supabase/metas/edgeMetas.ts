/**
 * F5-10 P5 (Issue #218), Bloco 1/S2 — adapter de cliente da Edge Function `metas`.
 *
 * ÚNICA superfície soberana de metas no cliente (leitura E mutação — D22-A):
 * nenhuma página/componente fala com a Edge por conta própria e nada aqui decide
 * autorização — o corpo carrega apenas INTENÇÃO (alvo UUID, versão esperada,
 * campos de domínio, motivo, `operation_id`) e a decisão é sempre server-side.
 *
 * Fail-closed: erro de transporte, resposta fora do contrato ou código
 * desconhecido viram `{ ok: false }` com código público (F0-05) — nunca uma
 * suposição de sucesso. O `service_role` não existe deste lado e NÃO há fallback
 * (nada de `localStorage`, cache, retentativa alternativa ou leitura direta de
 * tabela). A fronteira não inventa campos: devolve o `resultado` bruto da RPC.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type {
  CodigoPublico,
  OperacaoMeta,
  PapelAprovacaoMeta,
  TipoMetaSoberana,
} from "./contrato";

export const FUNCAO_METAS = "metas";

export interface RespostaEdgeMetas {
  readonly ok?: boolean;
  readonly operacao?: string;
  readonly resultado?: unknown;
  readonly error?: { readonly code?: unknown; readonly message?: unknown };
}

export type ResultadoEdgeMetas<T> =
  | { readonly ok: true; readonly data: T }
  | {
      readonly ok: false;
      readonly error: { readonly code: CodigoPublico; readonly message: string };
    };

const CODIGOS: readonly CodigoPublico[] = [
  "FORBIDDEN",
  "NOT_FOUND",
  "CONFLICT",
  "INVALID_INPUT",
  "INTERNAL",
  "NOT_AUTHORIZED",
  "METHOD_NOT_ALLOWED",
];

function codigoPublico(valor: unknown): CodigoPublico {
  return typeof valor === "string" && (CODIGOS as readonly string[]).includes(valor)
    ? (valor as CodigoPublico)
    : "FORBIDDEN";
}

/** Entrada de `goal.criar` (a meta ainda não existe; o dono é revalidado SELF). */
export interface EntradaCriarMeta {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly collaboratorId: string;
  readonly tipo: TipoMetaSoberana;
  readonly descricao: string;
  readonly kpi: string;
  readonly valorAlvo: string;
  readonly operationId: string;
}

/** Base das operações sobre meta EXISTENTE (`goal_id` + versão esperada — D12). */
export interface EntradaMetaComVersao {
  readonly organizationId: string;
  readonly goalId: string;
  readonly expectedVersion: number;
  readonly operationId: string;
}

export interface EntradaEditarMeta extends EntradaMetaComVersao {
  readonly descricao: string;
  readonly kpi: string;
  readonly valorAlvo: string;
}

export interface EntradaAtualizarProgressoMeta extends EntradaMetaComVersao {
  readonly resultadoAtual: string;
  readonly progressoPercentual: number;
}

export interface EntradaFinalizarMeta extends EntradaMetaComVersao {
  readonly resultadoFinal: string;
  readonly atingida: boolean;
}

/** A RPC aceita `p_motivo` nulo na revisão de fechamento — motivo é opcional. */
export interface EntradaRevisarFinalizacaoMeta extends EntradaFinalizarMeta {
  readonly motivo?: string;
}

export interface EntradaExcluirMeta extends EntradaMetaComVersao {
  readonly motivo: string;
}

/** A RPC aceita `p_motivo` nulo na aprovação — motivo é opcional. */
export interface EntradaAprovarMeta extends EntradaMetaComVersao {
  readonly papel: PapelAprovacaoMeta;
  readonly motivo?: string;
}

/** `expected_version` aqui é a versão DO CICLO (D21), não de uma meta. */
export interface EntradaDefinirLimitesDoCiclo {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly tipo: TipoMetaSoberana;
  readonly quantidade: number;
  readonly motivo: string;
  readonly expectedVersion: number;
  readonly operationId: string;
}

/** Leitura por escopo: sempre recortada por CICLO (§11/D22). */
export interface EntradaListarMetasPorEscopo {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly operationId: string;
}

/**
 * Superfície da Edge `metas`. Cada método devolve o `resultado` bruto da RPC
 * (ex.: `{ goal_id, version, status }`) projetado pelo chamador — a fronteira
 * não inventa campos.
 */
export interface EdgeMetas {
  criar(entrada: EntradaCriarMeta): Promise<ResultadoEdgeMetas<unknown>>;
  editar(entrada: EntradaEditarMeta): Promise<ResultadoEdgeMetas<unknown>>;
  atualizarProgresso(
    entrada: EntradaAtualizarProgressoMeta
  ): Promise<ResultadoEdgeMetas<unknown>>;
  finalizar(entrada: EntradaFinalizarMeta): Promise<ResultadoEdgeMetas<unknown>>;
  revisarFinalizacao(
    entrada: EntradaRevisarFinalizacaoMeta
  ): Promise<ResultadoEdgeMetas<unknown>>;
  excluir(entrada: EntradaExcluirMeta): Promise<ResultadoEdgeMetas<unknown>>;
  aprovar(entrada: EntradaAprovarMeta): Promise<ResultadoEdgeMetas<unknown>>;
  definirLimitesDoCiclo(
    entrada: EntradaDefinirLimitesDoCiclo
  ): Promise<ResultadoEdgeMetas<unknown>>;
  listarPorEscopo(
    entrada: EntradaListarMetasPorEscopo
  ): Promise<ResultadoEdgeMetas<unknown>>;
}

function corpo(
  operacao: OperacaoMeta,
  organizationId: string,
  operationId: string,
  extras: Record<string, unknown> = {}
): Record<string, unknown> {
  return {
    organization_id: organizationId,
    operacao,
    operation_id: operationId,
    ...extras,
  };
}

/**
 * Extrai o trecho de `resultado` opcional (motivo) sem enviar a chave quando ela
 * não existe: a fronteira não inventa campos nem envia `undefined`.
 */
function comMotivo(motivo: string | undefined): Record<string, unknown> {
  return motivo === undefined ? {} : { motivo };
}

export function criarEdgeMetas(cliente: SupabaseClient): EdgeMetas {
  async function invocar(
    corpoRequisicao: Record<string, unknown>
  ): Promise<ResultadoEdgeMetas<unknown>> {
    const { data, error } = await cliente.functions.invoke<RespostaEdgeMetas>(FUNCAO_METAS, {
      body: corpoRequisicao,
    });

    if (error) {
      // A Edge devolve `{ error: { code, message } }`; o supabase-js expõe o
      // corpo em `error.context` quando o status não é 2xx.
      const contexto = (error as { context?: RespostaEdgeMetas }).context;
      const corpoErro = contexto?.error;
      return {
        ok: false,
        error: {
          code: codigoPublico(corpoErro?.code),
          message:
            typeof corpoErro?.message === "string"
              ? corpoErro.message
              : "Operação de meta recusada.",
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
              : "Operação de meta recusada.",
        },
      };
    }

    // 2xx fora do contrato (sem `ok: true` ou sem a PRÓPRIA chave `resultado`)
    // NÃO é sucesso presumido — `resultado: null` é aceito como sucesso.
    if (data?.ok !== true || !Object.prototype.hasOwnProperty.call(data, "resultado")) {
      return {
        ok: false,
        error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
      };
    }

    return { ok: true, data: data.resultado ?? null };
  }

  return {
    criar: (entrada) =>
      invocar(
        corpo("goal.criar", entrada.organizationId, entrada.operationId, {
          cycle_id: entrada.cycleId,
          collaborator_id: entrada.collaboratorId,
          tipo: entrada.tipo,
          descricao: entrada.descricao,
          kpi: entrada.kpi,
          valor_alvo: entrada.valorAlvo,
        })
      ),

    editar: (entrada) =>
      invocar(
        corpo("goal.editar", entrada.organizationId, entrada.operationId, {
          goal_id: entrada.goalId,
          descricao: entrada.descricao,
          kpi: entrada.kpi,
          valor_alvo: entrada.valorAlvo,
          expected_version: entrada.expectedVersion,
        })
      ),

    atualizarProgresso: (entrada) =>
      invocar(
        corpo("goal.atualizar_progresso", entrada.organizationId, entrada.operationId, {
          goal_id: entrada.goalId,
          resultado_atual: entrada.resultadoAtual,
          progresso_percentual: entrada.progressoPercentual,
          expected_version: entrada.expectedVersion,
        })
      ),

    finalizar: (entrada) =>
      invocar(
        corpo("goal.finalizar", entrada.organizationId, entrada.operationId, {
          goal_id: entrada.goalId,
          resultado_final: entrada.resultadoFinal,
          atingida: entrada.atingida,
          expected_version: entrada.expectedVersion,
        })
      ),

    revisarFinalizacao: (entrada) =>
      invocar(
        corpo("goal.revisar_finalizacao", entrada.organizationId, entrada.operationId, {
          goal_id: entrada.goalId,
          resultado_final: entrada.resultadoFinal,
          atingida: entrada.atingida,
          expected_version: entrada.expectedVersion,
          ...comMotivo(entrada.motivo),
        })
      ),

    excluir: (entrada) =>
      invocar(
        corpo("goal.excluir", entrada.organizationId, entrada.operationId, {
          goal_id: entrada.goalId,
          motivo: entrada.motivo,
          expected_version: entrada.expectedVersion,
        })
      ),

    aprovar: (entrada) =>
      invocar(
        corpo("goal.aprovar", entrada.organizationId, entrada.operationId, {
          goal_id: entrada.goalId,
          papel: entrada.papel,
          expected_version: entrada.expectedVersion,
          ...comMotivo(entrada.motivo),
        })
      ),

    definirLimitesDoCiclo: (entrada) =>
      invocar(
        corpo("goal.definir_limites_do_ciclo", entrada.organizationId, entrada.operationId, {
          cycle_id: entrada.cycleId,
          tipo: entrada.tipo,
          quantidade: entrada.quantidade,
          motivo: entrada.motivo,
          expected_version: entrada.expectedVersion,
        })
      ),

    listarPorEscopo: (entrada) =>
      invocar(
        corpo("goal.listar_por_escopo", entrada.organizationId, entrada.operationId, {
          cycle_id: entrada.cycleId,
        })
      ),
  };
}
