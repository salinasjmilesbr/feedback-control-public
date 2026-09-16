/**
 * F5-11 P4 — adapter de cliente da Edge Function `observacoes`.
 *
 * ÚNICA superfície soberana de observações no cliente (leitura E mutação):
 * nenhuma página/componente fala com a Edge por conta própria e nada aqui decide
 * autorização — o corpo carrega apenas INTENÇÃO (alvo UUID, versão esperada,
 * campos de domínio da observação, motivo, escopo de listagem, `operation_id`) e
 * a decisão é sempre server-side.
 *
 * Fail-closed: erro de transporte, resposta fora do contrato ou código
 * desconhecido viram `{ ok: false }` com código público (F0-05) — nunca uma
 * suposição de sucesso. A credencial privilegiada não existe deste lado, não há
 * fallback (nada de armazenamento local, cache, retentativa alternativa ou
 * leitura direta de tabela) e nenhuma RPC do banco é chamada pelo browser. A
 * fronteira não inventa campos: devolve o `resultado` bruto da RPC.
 */
import type { SupabaseClient } from "@supabase/supabase-js";
import { corpoDeErroEdge } from "../errosEdge";
import type {
  CodigoPublico,
  EscopoObservacao,
  OperacaoObservacao,
  TipoObservacaoSoberana,
} from "./contrato";

export const FUNCAO_OBSERVACOES = "observacoes";

export interface RespostaEdgeObservacoes {
  /**
   * `unknown` de propósito: o corpo chega de `functions.invoke` sem tipo real e
   * a fronteira só aceita SUCESSO quando o valor é EXATAMENTE `true`
   * (`data?.ok !== true` ⇒ `INTERNAL`). Tipar como `boolean` daria a falsa
   * impressão de que o valor já foi validado antes da checagem.
   */
  readonly ok?: unknown;
  readonly operacao?: string;
  readonly resultado?: unknown;
  readonly error?: { readonly code?: unknown; readonly message?: unknown };
}

export type ResultadoEdgeObservacoes<T> =
  | { readonly ok: true; readonly data: T }
  | {
      readonly ok: false;
      readonly error: { readonly code: CodigoPublico; readonly message: string };
    };

/**
 * Lista FECHADA dos códigos públicos (F0-05). Código fora dela — inclusive um
 * código novo devolvido por uma Edge futura — vira `FORBIDDEN` (fail-closed):
 * nunca é repassado cru ao chamador.
 */
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

/** Entrada da criação (a observação ainda não existe; D2/D3). */
export interface EntradaCriarObservacao {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly collaboratorId: string;
  readonly tipo: TipoObservacaoSoberana;
  readonly texto: string;
  readonly operationId: string;
}

/** Base das mutações de observação EXISTENTE (`observation_id` + versão — D10). */
export interface EntradaObservacaoComVersao {
  readonly organizationId: string;
  readonly observationId: string;
  readonly expectedVersion: number;
  readonly operationId: string;
}

/** §7.5/D4: definição COMPLETA dos campos mutáveis (sem merge parcial). */
export interface EntradaEditarObservacao extends EntradaObservacaoComVersao {
  readonly tipo: TipoObservacaoSoberana;
  readonly texto: string;
  readonly comunicado: boolean;
}

/** D7: marcar/desmarcar o fato comunicado é `observation.edit`. */
export interface EntradaDefinirComunicadoObservacao extends EntradaObservacaoComVersao {
  readonly comunicado: boolean;
}

/** D8/D16: exclusão lógica com motivo OBRIGATÓRIO. */
export interface EntradaExcluirObservacao extends EntradaObservacaoComVersao {
  readonly motivo: string;
}

/** D8: revogação da exclusão — operação distinta, motivo OBRIGATÓRIO. */
export interface EntradaRevogarObservacao extends EntradaObservacaoComVersao {
  readonly motivo: string;
}

/** Leitura de UMA observação (visibilidade decidida na RPC soberana). */
export interface EntradaObterObservacao {
  readonly organizationId: string;
  readonly observationId: string;
  readonly operationId: string;
}

/**
 * §8 linha 1/2: listagem recortada por ESCOPO (allowlist fechada).
 *
 * `organizationalUnitId` é intenção OPCIONAL do recorte: quando ausente a chave
 * NÃO viaja no corpo (a fronteira não inventa campos). A DATA de referência não
 * é enviada pelo cliente — o instante da decisão é soberano (D21).
 */
export interface EntradaListarObservacoesPorEscopo {
  readonly organizationId: string;
  readonly escopo: EscopoObservacao;
  readonly organizationalUnitId?: string;
  readonly operationId: string;
}

/** §7.8/D6: a trilha append-only é a única fonte do histórico. */
export interface EntradaHistoricoObservacao {
  readonly organizationId: string;
  readonly observationId: string;
  readonly operationId: string;
}

/**
 * Superfície da Edge `observacoes`. Cada método devolve o `resultado` bruto da
 * RPC (ex.: `{ observation_id, version, comunicado }`) projetado pelo chamador —
 * a fronteira não inventa campos.
 */
export interface EdgeObservacoes {
  criar(entrada: EntradaCriarObservacao): Promise<ResultadoEdgeObservacoes<unknown>>;
  editar(entrada: EntradaEditarObservacao): Promise<ResultadoEdgeObservacoes<unknown>>;
  definirComunicado(
    entrada: EntradaDefinirComunicadoObservacao
  ): Promise<ResultadoEdgeObservacoes<unknown>>;
  excluir(entrada: EntradaExcluirObservacao): Promise<ResultadoEdgeObservacoes<unknown>>;
  revogar(entrada: EntradaRevogarObservacao): Promise<ResultadoEdgeObservacoes<unknown>>;
  obter(entrada: EntradaObterObservacao): Promise<ResultadoEdgeObservacoes<unknown>>;
  listarPorEscopo(
    entrada: EntradaListarObservacoesPorEscopo
  ): Promise<ResultadoEdgeObservacoes<unknown>>;
  historico(entrada: EntradaHistoricoObservacao): Promise<ResultadoEdgeObservacoes<unknown>>;
}

function corpo(
  operacao: OperacaoObservacao,
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
 * Recorte OPCIONAL da listagem: a unidade só entra no corpo quando informada —
 * a fronteira não envia `undefined` nem inventa a chave.
 */
function comUnidade(organizationalUnitId: string | undefined): Record<string, unknown> {
  return organizationalUnitId === undefined
    ? {}
    : { organizational_unit_id: organizationalUnitId };
}

export function criarEdgeObservacoes(cliente: SupabaseClient): EdgeObservacoes {
  async function invocar(
    corpoRequisicao: Record<string, unknown>
  ): Promise<ResultadoEdgeObservacoes<unknown>> {
    const { data, error } = await cliente.functions.invoke<RespostaEdgeObservacoes>(
      FUNCAO_OBSERVACOES,
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
              : "Operação de observação recusada.",
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
              : "Operação de observação recusada.",
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
        corpo("observacao.criar", entrada.organizationId, entrada.operationId, {
          cycle_id: entrada.cycleId,
          collaborator_id: entrada.collaboratorId,
          tipo: entrada.tipo,
          texto: entrada.texto,
        })
      ),

    editar: (entrada) =>
      invocar(
        corpo("observacao.editar", entrada.organizationId, entrada.operationId, {
          observation_id: entrada.observationId,
          tipo: entrada.tipo,
          texto: entrada.texto,
          comunicado: entrada.comunicado,
          expected_version: entrada.expectedVersion,
        })
      ),

    definirComunicado: (entrada) =>
      invocar(
        corpo(
          "observacao.definir_comunicado",
          entrada.organizationId,
          entrada.operationId,
          {
            observation_id: entrada.observationId,
            comunicado: entrada.comunicado,
            expected_version: entrada.expectedVersion,
          }
        )
      ),

    excluir: (entrada) =>
      invocar(
        corpo("observacao.excluir", entrada.organizationId, entrada.operationId, {
          observation_id: entrada.observationId,
          motivo: entrada.motivo,
          expected_version: entrada.expectedVersion,
        })
      ),

    revogar: (entrada) =>
      invocar(
        corpo("observacao.revogar", entrada.organizationId, entrada.operationId, {
          observation_id: entrada.observationId,
          motivo: entrada.motivo,
          expected_version: entrada.expectedVersion,
        })
      ),

    obter: (entrada) =>
      invocar(
        corpo("observacao.obter", entrada.organizationId, entrada.operationId, {
          observation_id: entrada.observationId,
        })
      ),

    listarPorEscopo: (entrada) =>
      invocar(
        corpo("observacao.listar_por_escopo", entrada.organizationId, entrada.operationId, {
          escopo: entrada.escopo,
          ...comUnidade(entrada.organizationalUnitId),
        })
      ),

    historico: (entrada) =>
      invocar(
        corpo("observacao.historico", entrada.organizationId, entrada.operationId, {
          observation_id: entrada.observationId,
        })
      ),
  };
}
