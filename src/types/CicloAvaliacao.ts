export type StatusCicloAvaliacao =
  | "PLANEJADO"
  | "ATIVO"
  | "ENCERRADO"
  | "CANCELADO";

export interface CancelamentoCiclo {
  motivo: string;
  autorMatricula: number;
  autorNome: string;
  data: string;
}

export interface EncerramentoCiclo {
  data: string;
  encerradoComPendencias: boolean;
  quantidadePendencias: number;
}

export interface ReaberturaCiclo {
  motivo: string;
  autorMatricula: number;
  autorNome: string;
  data: string;
}

export interface ImpactoTemporalPeriodoCiclo {
  avaliacoes: { quantidade: number; ids: string[] };
  metas: { quantidade: number; ids: string[] };
  observacoes: { quantidade: number; ids: string[] };
  total: number;
}

export interface CorrecaoPeriodoCiclo {
  periodoAnterior: {
    dataInicio?: string;
    dataFim?: string;
  };
  novoPeriodo: {
    dataInicio: string;
    dataFim: string;
  };
  justificativa: string;
  autorMatricula: number;
  autorNome: string;
  data: string;
  impacto: ImpactoTemporalPeriodoCiclo;
}

export interface CicloAvaliacao {
  id: string;
  ano: number;
  ciclo: 1 | 2 | 3;
  dataInicio?: string;
  dataFim?: string;

  // Quantidades máximas de metas permitidas no ciclo.
  // Opcionais para manter compatibilidade com ciclos antigos.
  quantidadeMetasNegocio?: 0 | 1 | 2 | 3;
  quantidadeMetasIndividuais?: 0 | 1 | 2 | 3;
  status: StatusCicloAvaliacao;
  dataCriacao: string;
  dataUltimaAtualizacao: string;
  dataAtivacao?: string;
  dataEncerramento?: string;
  encerradoComPendencias?: boolean;
  quantidadePendencias?: number;
  cancelamento?: CancelamentoCiclo;
  encerramentos?: EncerramentoCiclo[];
  reaberturas?: ReaberturaCiclo[];
  correcoesPeriodo?: CorrecaoPeriodoCiclo[];
}
