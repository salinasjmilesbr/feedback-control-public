export type TipoObservacao =
  | "POSITIVA"
  | "NEUTRA"
  | "NEGATIVA";

export type AcaoHistoricoObservacao =
  | "CRIACAO"
  | "EDICAO"
  | "EXCLUSAO";

export interface HistoricoObservacao {
  id: string;
  acao: AcaoHistoricoObservacao;
  data: string;
  autorMatricula: number;
  autorNome: string;
  textoAnterior?: string;
  tipoAnterior?: TipoObservacao;
  comunicadoAnterior?: boolean;
}

export interface Observacao {
  id: string;
  colaboradorMatricula: number;
  tipo: TipoObservacao;
  texto: string;
  comunicado: boolean;

  autorMatricula: number;
  autorNome: string;

  dataCriacao: string;
  dataUltimaAtualizacao: string;

  excluida: boolean;
  dataExclusao?: string;
  excluidaPorMatricula?: number;
  excluidaPorNome?: string;

  historico: HistoricoObservacao[];
}
