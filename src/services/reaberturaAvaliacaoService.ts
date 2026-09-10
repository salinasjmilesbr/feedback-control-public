/**
 * F5-06 (Issue #103) — REABERTURA SOBERANA da avaliação.
 *
 * A decisão de autorização NÃO é tomada aqui: o ator, o tenant e a relação com o
 * avaliado são revalidados server-side (ActorContext/ResourceContext reais) e o
 * Policy Engine decide ALLOW/DENY com a capability `evaluation.reopen` e o scope
 * da cadeia de gestão. O cliente apenas envia a INTENÇÃO (id + motivo +
 * organização ativa) e traduz o erro público.
 *
 * Nenhuma escrita local acontece — nem antes, nem em caso de falha (sem
 * dual-write, sem fallback; D12/§11.3). O motivo é obrigatório, o status
 * `CONCLUIDA` é exigido pelo domínio server-side e o histórico é preservado com
 * evento auditado na mesma transação (D7/D8/D26).
 */

import {
  reabrirAvaliacaoSoberana,
  type DependenciasAcessoAvaliacoes,
} from "./acessoAvaliacoesSoberanas";

export interface ResultadoReaberturaAvaliacao {
  readonly ok: boolean;
  readonly erro?: string;
}

export async function reabrirAvaliacao(
  feedbackId: string,
  motivoInformado: string,
  organizationId: string,
  deps: DependenciasAcessoAvaliacoes = {}
): Promise<ResultadoReaberturaAvaliacao> {
  const motivo = motivoInformado.trim();
  if (!motivo) {
    throw new Error("Informe o motivo da reabertura.");
  }

  const resultado = await reabrirAvaliacaoSoberana(
    { organizationId, evaluationId: feedbackId, motivo },
    deps
  );

  return resultado.ok ? { ok: true } : { ok: false, erro: resultado.erro };
}
