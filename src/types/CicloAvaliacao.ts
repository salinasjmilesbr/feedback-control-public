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
}
