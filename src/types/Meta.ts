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

  // Campos preparados para a etapa de acompanhamento.
  resultadoAtual?: string;
  resultadoFinal?: string;
  atingida?: boolean;

  dataCriacao: string;
  dataUltimaAtualizacao: string;

  excluida: boolean;
  dataExclusao?: string;

  historico: HistoricoMeta[];
}
