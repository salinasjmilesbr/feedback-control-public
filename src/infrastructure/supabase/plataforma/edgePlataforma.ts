/**
 * F6-A03 (Issue #266) — adapter de cliente da Edge Function
 * `provisionar-organizacao`.
 *
 * ÚNICA superfície do PLANO DE PLATAFORMA no cliente: nenhuma página fala com a
 * Edge por conta própria e nada aqui decide autorização — o corpo carrega apenas
 * INTENÇÃO (nome da organização, identificação do primeiro Admin, `operation_id`)
 * e a decisão é sempre server-side.
 *
 * Fail-closed: erro de transporte, resposta fora do contrato ou código
 * desconhecido viram `{ ok: false }` com código público (F0-05) — nunca uma
 * suposição de sucesso. A credencial privilegiada não existe deste lado, não há
 * fallback (nada de armazenamento local, cache, retentativa alternativa ou
 * leitura direta de tabela) e nenhuma RPC do banco é chamada pelo browser.
 */
import type { SupabaseClient } from "@supabase/supabase-js";
import { corpoDeErroEdge } from "../errosEdge";
import {
  OPERACAO_OPERADOR_ATUAL,
  OPERACAO_PROVISIONAR_ORGANIZACAO,
  eCodigoPublico,
  type CodigoPublico,
} from "./contrato";
import type { NovaOrganizacaoPlataforma } from "../../../application/ports/ProvisionamentoPlataforma";

export const FUNCAO_PLATAFORMA = "provisionar-organizacao";

export interface RespostaEdgePlataforma {
  /**
   * `unknown` de propósito: o corpo chega de `functions.invoke` sem tipo real e
   * a fronteira só aceita SUCESSO quando o valor é EXATAMENTE `true`
   * (`data?.ok !== true` ⇒ `INTERNAL`).
   */
  readonly ok?: unknown;
  readonly operacao?: unknown;
  readonly resultado?: unknown;
  readonly error?: { readonly code?: unknown; readonly message?: unknown };
}

export type ResultadoEdgePlataforma<T> =
  | { readonly ok: true; readonly data: T }
  | {
      readonly ok: false;
      readonly error: { readonly code: CodigoPublico; readonly message: string };
    };

/** Entrada de transporte da operação de provisionamento. */
export interface CorpoProvisaoPlataforma {
  readonly operationId: string;
  readonly organizationName: string;
  /** F6-A11 (D22/D23): nome humano do primeiro Admin (intenção, não autoridade). */
  readonly founderFullName: string;
  /** F6-A11 (D23/D28): matrícula declarada do primeiro Admin na nova organização. */
  readonly founderMatricula: string;
  readonly founderUserId?: string;
  readonly founderEmail?: string;
}

export interface EdgePlataforma {
  provisionarOrganizacao(
    entrada: CorpoProvisaoPlataforma
  ): Promise<ResultadoEdgePlataforma<unknown>>;
  operadorAtual(): Promise<ResultadoEdgePlataforma<unknown>>;
}

/**
 * Código público fechado: valor fora da lista — inclusive um código novo
 * devolvido por uma Edge futura — vira `INTERNAL` (fail-closed), nunca é
 * repassado cru ao chamador (critério 25 do contrato).
 */
function codigoPublico(valor: unknown): CodigoPublico {
  return eCodigoPublico(valor) ? valor : "INTERNAL";
}

/**
 * Corpo da provisão: a identificação do primeiro Admin viaja em UMA única forma
 * (a fronteira não envia `undefined` nem inventa a outra chave). A identidade
 * funcional mínima (nome humano + matrícula) viaja SEMPRE, como intenção.
 */
export function corpoDaProvisao(
  entrada: NovaOrganizacaoPlataforma
): Record<string, unknown> {
  const corpo: Record<string, unknown> = {
    operacao: OPERACAO_PROVISIONAR_ORGANIZACAO,
    operation_id: entrada.operationId,
    organization_name: entrada.organizationName,
    founder_full_name: entrada.founderFullName,
    founder_matricula: entrada.founderMatricula,
  };
  if (entrada.founderUserId !== undefined) {
    corpo.founder_user_id = entrada.founderUserId;
  } else if (entrada.founderEmail !== undefined) {
    corpo.founder_email = entrada.founderEmail;
  }
  return corpo;
}

export function criarEdgePlataforma(cliente: SupabaseClient): EdgePlataforma {
  async function invocar(
    corpoRequisicao: Record<string, unknown>
  ): Promise<ResultadoEdgePlataforma<unknown>> {
    const { data, error } = await cliente.functions.invoke<RespostaEdgePlataforma>(
      FUNCAO_PLATAFORMA,
      { body: corpoRequisicao }
    );

    if (error) {
      // `FunctionsHttpError.context` é um `Response`: o corpo `{ error: { code,
      // message } }` precisa ser LIDO (Issue #221 / `errosEdge.ts`).
      const corpoErro = await corpoDeErroEdge(error);
      return {
        ok: false,
        error: {
          code: codigoPublico(corpoErro?.code),
          message:
            typeof corpoErro?.message === "string"
              ? corpoErro.message
              : "Operação de plataforma recusada.",
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
              : "Operação de plataforma recusada.",
        },
      };
    }

    // 2xx fora do contrato (sem `ok: true` ou sem a PRÓPRIA chave `resultado`)
    // NÃO é sucesso presumido.
    if (data?.ok !== true || !Object.prototype.hasOwnProperty.call(data, "resultado")) {
      return {
        ok: false,
        error: { code: "INTERNAL", message: "Resposta inesperada do servidor." },
      };
    }

    return { ok: true, data: data.resultado ?? null };
  }

  return {
    provisionarOrganizacao: (entrada) => invocar(corpoDaProvisao(entrada)),
    operadorAtual: () => invocar({ operacao: OPERACAO_OPERADOR_ATUAL }),
  };
}
