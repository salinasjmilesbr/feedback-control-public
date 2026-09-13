/**
 * F5-09 P7 (Issue #202) — adapter de cliente da Edge Function `ciclos`.
 *
 * ÚNICA superfície de ESCRITA soberana de ciclo no cliente (§13.5): nenhuma
 * página/componente fala com a Edge por conta própria e nada aqui decide
 * autorização — o corpo carrega apenas INTENÇÃO (alvo UUID, versão esperada,
 * motivo, `operationId`) e a decisão é sempre server-side.
 *
 * Fail-closed: erro de transporte, resposta fora do contrato ou código
 * desconhecido viram `{ ok: false }` com código público (F0-05) — nunca uma
 * suposição de sucesso. O `service_role` não existe deste lado.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { CodigoPublico, OperacaoCiclo } from "./contrato";

export const FUNCAO_CICLOS = "ciclos";

export interface RespostaEdgeCiclos {
  readonly ok?: boolean;
  readonly operacao?: string;
  readonly resultado?: unknown;
  readonly error?: { readonly code?: unknown; readonly message?: unknown };
}

export type ResultadoEdgeCiclos<T> =
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

/** Entrada de `cycle.criar` (intenção; o ciclo ainda não existe — D21). */
export interface EntradaCriarCiclo {
  readonly organizationId: string;
  readonly ano: number;
  readonly numero: 1 | 2 | 3;
  readonly dataInicio: string;
  readonly dataFim: string;
  readonly operationId: string;
}

export interface EntradaEditarCiclo {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly ano: number;
  readonly numero: 1 | 2 | 3;
  readonly dataInicio: string;
  readonly dataFim: string;
  readonly expectedVersion: number;
  readonly operationId: string;
}

export interface EntradaCicloComVersao {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly expectedVersion: number;
  readonly operationId: string;
}

export interface EntradaCicloComMotivo extends EntradaCicloComVersao {
  readonly motivo: string;
}

export interface EntradaCorrigirPeriodo extends EntradaCicloComVersao {
  readonly dataInicio: string;
  readonly dataFim: string;
  readonly justificativa: string;
}

export interface EntradaIncluirAdmissao extends EntradaCicloComVersao {
  readonly motivo: string;
  /** Exatamente um: UUID do colaborador (preferencial) ou matrícula (intenção). */
  readonly collaboratorId?: string;
  readonly matricula?: number | string;
}

/**
 * Superfície de escrita da Edge `ciclos`. Cada método devolve o `resultado`
 * bruto da RPC (ex.: `{ version }`, `{ cycleId, version }`) projetado pelo
 * chamador — a fronteira não inventa campos.
 */
export interface EdgeCiclos {
  criar(entrada: EntradaCriarCiclo): Promise<ResultadoEdgeCiclos<unknown>>;
  editar(entrada: EntradaEditarCiclo): Promise<ResultadoEdgeCiclos<unknown>>;
  ativar(entrada: EntradaCicloComVersao): Promise<ResultadoEdgeCiclos<unknown>>;
  encerrar(entrada: EntradaCicloComMotivo): Promise<ResultadoEdgeCiclos<unknown>>;
  cancelar(entrada: EntradaCicloComMotivo): Promise<ResultadoEdgeCiclos<unknown>>;
  reabrir(entrada: EntradaCicloComMotivo): Promise<ResultadoEdgeCiclos<unknown>>;
  corrigirPeriodo(entrada: EntradaCorrigirPeriodo): Promise<ResultadoEdgeCiclos<unknown>>;
  incluirAdmissao(entrada: EntradaIncluirAdmissao): Promise<ResultadoEdgeCiclos<unknown>>;
}

function corpo(
  operacao: OperacaoCiclo,
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

export function criarEdgeCiclos(cliente: SupabaseClient): EdgeCiclos {
  async function invocar(
    corpoRequisicao: Record<string, unknown>
  ): Promise<ResultadoEdgeCiclos<unknown>> {
    const { data, error } = await cliente.functions.invoke<RespostaEdgeCiclos>(FUNCAO_CICLOS, {
      body: corpoRequisicao,
    });

    if (error) {
      // A Edge devolve `{ error: { code, message } }`; o supabase-js expõe o
      // corpo em `error.context` quando o status não é 2xx.
      const contexto = (error as { context?: RespostaEdgeCiclos }).context;
      const corpoErro = contexto?.error;
      return {
        ok: false,
        error: {
          code: codigoPublico(corpoErro?.code),
          message:
            typeof corpoErro?.message === "string"
              ? corpoErro.message
              : "Operação de ciclo recusada.",
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
              : "Operação de ciclo recusada.",
        },
      };
    }

    // 2xx fora do contrato (sem `ok: true`) NÃO é sucesso presumido.
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
        corpo("cycle.criar", entrada.organizationId, entrada.operationId, {
          ano: entrada.ano,
          numero: entrada.numero,
          data_inicio: entrada.dataInicio,
          data_fim: entrada.dataFim,
        })
      ),

    editar: (entrada) =>
      invocar(
        corpo("cycle.editar", entrada.organizationId, entrada.operationId, {
          cycle_id: entrada.cycleId,
          ano: entrada.ano,
          numero: entrada.numero,
          data_inicio: entrada.dataInicio,
          data_fim: entrada.dataFim,
          expected_version: entrada.expectedVersion,
        })
      ),

    ativar: (entrada) =>
      invocar(
        corpo("cycle.ativar", entrada.organizationId, entrada.operationId, {
          cycle_id: entrada.cycleId,
          expected_version: entrada.expectedVersion,
        })
      ),

    encerrar: (entrada) =>
      invocar(
        corpo("cycle.encerrar", entrada.organizationId, entrada.operationId, {
          cycle_id: entrada.cycleId,
          expected_version: entrada.expectedVersion,
          motivo: entrada.motivo,
        })
      ),

    cancelar: (entrada) =>
      invocar(
        corpo("cycle.cancelar", entrada.organizationId, entrada.operationId, {
          cycle_id: entrada.cycleId,
          expected_version: entrada.expectedVersion,
          motivo: entrada.motivo,
        })
      ),

    reabrir: (entrada) =>
      invocar(
        corpo("cycle.reabrir", entrada.organizationId, entrada.operationId, {
          cycle_id: entrada.cycleId,
          expected_version: entrada.expectedVersion,
          motivo: entrada.motivo,
        })
      ),

    corrigirPeriodo: (entrada) =>
      invocar(
        corpo("cycle.corrigir_periodo", entrada.organizationId, entrada.operationId, {
          cycle_id: entrada.cycleId,
          data_inicio: entrada.dataInicio,
          data_fim: entrada.dataFim,
          justificativa: entrada.justificativa,
          expected_version: entrada.expectedVersion,
        })
      ),

    incluirAdmissao: (entrada) =>
      invocar(
        corpo("cycle.admissao.incluir", entrada.organizationId, entrada.operationId, {
          cycle_id: entrada.cycleId,
          expected_version: entrada.expectedVersion,
          motivo: entrada.motivo,
          ...(entrada.collaboratorId
            ? { collaborator_id: entrada.collaboratorId }
            : { matricula: entrada.matricula }),
        })
      ),
  };
}
