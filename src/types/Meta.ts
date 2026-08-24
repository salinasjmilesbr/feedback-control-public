export type TipoMeta =
  | "NEGOCIO_PROJETO"
  | "INDIVIDUAL";

export type StatusMeta =
  | "EM_ANDAMENTO"
  | "ATINGIDA"
  | "NAO_ATINGIDA";

export type AcaoHistoricoMeta =
  | "CRIACAO"
  | "EDICAO"
  | "ATUALIZACAO_PROGRESSO"
  | "FINALIZACAO"
  | "EXCLUSAO";

export interface HistoricoMeta {
  id: string;
  acao: AcaoHistoricoMeta;
  data: string;
  autorMatricula: number;
  autorNome: string;

  descricaoAnterior?: string;
  kpiAnterior?: string;
  valorAlvoAnterior?: string;
  resultadoAtualAnterior?: string;
  progressoPercentualAnterior?: number;
  resultadoFinalAnterior?: string;
  atingidaAnterior?: boolean;
}

export interface Meta {
  id: string;
  colaboradorMatricula: number;
  colaboradorNome: string;

  cicloId: string;
  ano: number;
  ciclo: 1 | 2 | 3;

  tipo: TipoMeta;

  descricao: string;
  kpi: string;
  valorAlvo: string;

  status: StatusMeta;

  // Acompanhamento durante o ciclo.
  resultadoAtual?: string;
  progressoPercentual?: number;
  dataUltimoAcompanhamento?: string;

  // Campos preparados para o fechamento da meta.
  resultadoFinal?: string;
  atingida?: boolean;
  dataFechamento?: string;

  dataCriacao: string;
  dataUltimaAtualizacao: string;

  excluida: boolean;
  dataExclusao?: string;

  historico: HistoricoMeta[];
}
