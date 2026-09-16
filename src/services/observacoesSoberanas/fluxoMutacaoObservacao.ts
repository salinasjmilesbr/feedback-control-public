/**
 * F5-11 P5 (Issue #250), L3 — FLUXO de mutação do painel de observações.
 *
 * A tela NÃO contém regra de negócio nem autorização: ela coleta a INTENÇÃO do
 * gestor (tipo, texto, comunicado, motivo) e delega ao CONTROLADOR soberano. Este
 * módulo é essa delegação, em um ponto único e testável:
 *
 * - a versão esperada (`expectedVersion`) é derivada da LEITURA soberana pelo
 *   próprio controlador — nunca vem do browser (D10);
 * - a negação é FAIL-CLOSED: devolve `{ ok: false, error: { code, mensagem } }`
 *   (código público + mensagem estável do controlador) e **nenhum** dado de
 *   sucesso. Não existe fallback local, dual-read nem "estado otimista";
 * - o painel só recarrega a lista quando `ok === true`; portanto uma mutação
 *   negada NÃO altera a lista exibida.
 *
 * Nada aqui decide autorização: quem decide é a Edge/RPC `observacao_*` e o
 * resultado apenas é apresentado.
 */

import type {
  ObservacaoMutadaSoberana,
  ObservacaoSoberana,
} from "../../application/ports/ObservationRepository";
import type {
  ControladorObservacoes,
  ResultadoObservacoesUi,
} from "./controladorObservacoes";
import type { TipoObservacaoSoberana } from "../../infrastructure/supabase/observacoes/contrato";

/** Contexto soberano do painel (organização, alvo e ciclo de CRIAÇÃO). */
export interface ContextoMutacaoObservacao {
  readonly controlador: ControladorObservacoes;
  /** Organização ativa — INTENÇÃO de UX (a fronteira revalida o tenant). */
  readonly organizationId: string;
  /** Colaborador-ALVO (`collaborators.id`) — só é usado na CRIAÇÃO (D4). */
  readonly collaboratorId: string;
  /** Ciclo soberano da CRIAÇÃO (`evaluation_cycles.id`) — ausente ⇒ não cria. */
  readonly cycleId?: string;
}

/** Intenção de criação/edição (definição completa dos campos mutáveis — D4). */
export interface IntencaoDefinicaoObservacao {
  readonly tipo: TipoObservacaoSoberana;
  readonly texto: string;
  readonly comunicado?: boolean;
}

/**
 * Cria a observação soberana. SEM ciclo informado a intenção é RECUSADA antes da
 * fronteira (`INVALID_INPUT` público) — nunca se inventa `cycle_id` (D2).
 */
export async function criarObservacaoSoberana(
  contexto: ContextoMutacaoObservacao,
  intencao: IntencaoDefinicaoObservacao
): Promise<ResultadoObservacoesUi<ObservacaoMutadaSoberana>> {
  if (!contexto.cycleId) {
    return {
      ok: false,
      error: { code: "INVALID_INPUT", mensagem: "Selecione o ciclo da observação." },
    };
  }

  return contexto.controlador.criar({
    organizationId: contexto.organizationId,
    cycleId: contexto.cycleId,
    collaboratorId: contexto.collaboratorId,
    tipo: intencao.tipo,
    texto: intencao.texto,
  });
}

/**
 * Edita a observação existente (definição COMPLETA: tipo/texto/comunicado). A
 * versão esperada vem da leitura soberana do controlador.
 */
export async function editarObservacaoSoberana(
  contexto: ContextoMutacaoObservacao,
  observacao: Pick<ObservacaoSoberana, "id">,
  intencao: IntencaoDefinicaoObservacao & { readonly comunicado: boolean }
): Promise<ResultadoObservacoesUi<ObservacaoMutadaSoberana>> {
  return contexto.controlador.editar({
    organizationId: contexto.organizationId,
    observationId: observacao.id,
    tipo: intencao.tipo,
    texto: intencao.texto,
    comunicado: intencao.comunicado,
  });
}

/**
 * Exclui (logicamente) a observação. SEM motivo a intenção é RECUSADA antes da
 * fronteira (D8/D16) — a validação de forma não substitui a decisão soberana.
 */
export async function excluirObservacaoSoberana(
  contexto: ContextoMutacaoObservacao,
  observacao: Pick<ObservacaoSoberana, "id">,
  motivo: string
): Promise<ResultadoObservacoesUi<ObservacaoMutadaSoberana>> {
  const limpo = motivo.trim();
  if (limpo.length === 0) {
    return {
      ok: false,
      error: { code: "INVALID_INPUT", mensagem: "Informe o motivo da exclusão." },
    };
  }

  return contexto.controlador.excluir({
    organizationId: contexto.organizationId,
    observationId: observacao.id,
    motivo: limpo,
  });
}

/**
 * Código público + mensagem do controlador, no formato exibido pelo painel
 * (fail-closed). Nunca "sucesso" e nunca detalhe do banco.
 */
export function mensagemDaFalha(
  falha: { readonly code: string; readonly mensagem: string }
): string {
  return `${falha.code}: ${falha.mensagem}`;
}
