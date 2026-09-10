/**
 * F5-06 (Issue #103) — CANCELAMENTO SOBERANO da avaliação.
 *
 * A decisão de autorização NÃO é tomada aqui: o ator, o tenant e a relação com o
 * avaliado são revalidados server-side (ActorContext/ResourceContext reais) e o
 * Policy Engine decide ALLOW/DENY. O cliente apenas envia a INTENÇÃO (id + motivo
 * + organização ativa) e traduz o erro público.
 *
 * Nenhuma escrita local acontece — nem antes, nem em caso de falha (sem
 * dual-write, sem fallback; D12/§11.3). O motivo é obrigatório e auditado com
 * autoria soberana e evento na mesma transação (D7/D26).
 */

import {
  cancelarAvaliacaoSoberana,
  type DependenciasAcessoAvaliacoes,
} from "./acessoAvaliacoesSoberanas";

export interface ResultadoCancelamentoAvaliacao {
  readonly ok: boolean;
  readonly erro?: string;
}

export async function cancelarAvaliacao(
  feedbackId: string,
  motivoInformado: string,
  organizationId: string,
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoCancelamentoAvaliacao> {
  const motivo = motivoInformado.trim();
  if (!motivo) {
    throw new Error("Informe o motivo do cancelamento.");
  }

  const resultado = await cancelarAvaliacaoSoberana(
    { organizationId, evaluationId: feedbackId, motivo },
    deps
  );

  return resultado.ok ? { ok: true } : { ok: false, erro: resultado.erro };
}
