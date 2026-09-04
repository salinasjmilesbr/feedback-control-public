import type { CicloAvaliacao, ImpactoTemporalPeriodoCiclo } from "../types/CicloAvaliacao";
import type { Feedback } from "../types/Feedback";
import type { Meta } from "../types/Meta";
import type { Observacao } from "../types/Observacao";

type RegistroComId = { id: string };

function timestampValido(data?: string): number | undefined {
  if (!data) return undefined;
  const timestamp = Date.parse(data);
  return Number.isNaN(timestamp) ? undefined : timestamp;
}

function idsForaDoPeriodo<T extends RegistroComId>(
  registros: readonly T[],
  dataInicio: string,
  dataFim: string,
  getDataReferencia: (registro: T) => string | undefined
): string[] {
  const inicio = Date.parse(`${dataInicio}T00:00:00.000Z`);
  const fim = Date.parse(`${dataFim}T23:59:59.999Z`);

  return registros
    .filter((registro) => {
      const referencia = timestampValido(getDataReferencia(registro));
      return referencia !== undefined && (referencia < inicio || referencia > fim);
    })
    .map((registro) => registro.id)
    .sort((a, b) => a.localeCompare(b));
}

export function calcularImpactoCorrecaoPeriodo(
  ciclo: CicloAvaliacao,
  dataInicio: string,
  dataFim: string,
  feedbacks: readonly Feedback[],
  metas: readonly Meta[],
  observacoes: readonly Observacao[]
): ImpactoTemporalPeriodoCiclo {
  const avaliacoesIds = idsForaDoPeriodo(
    feedbacks.filter(
      (feedback) => feedback.ano === ciclo.ano && feedback.ciclo === ciclo.ciclo
    ),
    dataInicio,
    dataFim,
    (feedback) =>
      timestampValido(feedback.dataCriacao) !== undefined
        ? feedback.dataCriacao
        : feedback.data
  );
  const metasIds = idsForaDoPeriodo(
    metas.filter((meta) => meta.cicloId === ciclo.id),
    dataInicio,
    dataFim,
    (meta) => meta.dataCriacao
  );
  const observacoesIds = idsForaDoPeriodo(
    observacoes.filter(
      (observacao) =>
        observacao.ano === ciclo.ano && observacao.ciclo === ciclo.ciclo
    ),
    dataInicio,
    dataFim,
    (observacao) => observacao.dataCriacao
  );

  return {
    avaliacoes: { quantidade: avaliacoesIds.length, ids: avaliacoesIds },
    metas: { quantidade: metasIds.length, ids: metasIds },
    observacoes: { quantidade: observacoesIds.length, ids: observacoesIds },
    total: avaliacoesIds.length + metasIds.length + observacoesIds.length,
  };
}
