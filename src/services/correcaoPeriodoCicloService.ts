import { authorize } from "../authorization/authorizationPolicy";
import type { AuthorizationContext } from "../authorization/AuthorizationContext";
import type { CicloAvaliacao, ImpactoTemporalPeriodoCiclo } from "../types/CicloAvaliacao";
import type { Colaborador } from "../types/Colaborador";
import {
  getCiclosAvaliacao,
  persistirCorrecaoPeriodoCicloAtivoInterno,
} from "./cicloAvaliacaoStorage";
import { getFeedbacks } from "./feedbackStorage";
import { getMetasDoCiclo } from "./metaStorage";
import { getObservacoesByCiclo } from "./observacaoStorage";
import { calcularImpactoCorrecaoPeriodo } from "./impactoCorrecaoPeriodoCiclo";

function getCicloAtivoPersistido(cicloId: string): CicloAvaliacao {
  const ciclo = getCiclosAvaliacao().find((item) => item.id === cicloId);
  if (!ciclo) throw new Error("Ciclo não encontrado.");
  if (ciclo.status !== "ATIVO") {
    throw new Error("Somente ciclos ativos podem ter o período corrigido.");
  }
  return ciclo;
}

function validarPeriodoCorrigido(
  ciclo: CicloAvaliacao,
  dataInicio: string,
  dataFim: string
) {
  if (!dataInicio || !dataFim) {
    throw new Error("Informe as datas de início e fim do ciclo.");
  }
  if (new Date(dataInicio).getTime() > new Date(dataFim).getTime()) {
    throw new Error("A data de início não pode ser posterior à data de fim.");
  }
  if (ciclo.dataInicio === dataInicio && ciclo.dataFim === dataFim) {
    throw new Error("Informe um período diferente do período atual.");
  }
}

export function analisarImpactoCorrecaoPeriodoCicloAtivo(
  cicloId: string,
  dataInicio: string,
  dataFim: string
): ImpactoTemporalPeriodoCiclo {
  const ciclo = getCicloAtivoPersistido(cicloId);
  validarPeriodoCorrigido(ciclo, dataInicio, dataFim);

  return calcularImpactoCorrecaoPeriodo(
    ciclo,
    dataInicio,
    dataFim,
    getFeedbacks(),
    getMetasDoCiclo(ciclo.id, true),
    getObservacoesByCiclo(ciclo.ano, ciclo.ciclo, true)
  );
}

export function corrigirPeriodoCicloAtivo(
  cicloId: string,
  dataInicio: string,
  dataFim: string,
  justificativaInformada: string,
  autor: Colaborador
): CicloAvaliacao {
  const justificativa = justificativaInformada.trim();
  if (!justificativa) {
    throw new Error("Informe a justificativa da correção do período.");
  }

  const ciclo = getCicloAtivoPersistido(cicloId);
  const context: AuthorizationContext = {
    actor: {
      matricula: autor.matricula,
      funcao: autor.funcao,
      status: autor.status,
    },
  };
  authorize(context, "cycle.period.correct.manager", {
    kind: "cycle",
    cycle: ciclo,
  });
  validarPeriodoCorrigido(ciclo, dataInicio, dataFim);

  const impacto = analisarImpactoCorrecaoPeriodoCicloAtivo(
    ciclo.id,
    dataInicio,
    dataFim
  );

  return persistirCorrecaoPeriodoCicloAtivoInterno(
    ciclo.id,
    dataInicio,
    dataFim,
    justificativa,
    autor.matricula,
    autor.nome,
    new Date().toISOString(),
    impacto
  );
}
