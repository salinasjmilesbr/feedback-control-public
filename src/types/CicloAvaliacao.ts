export type StatusCicloAvaliacao =
  | "PLANEJADO"
  | "ATIVO"
  | "ENCERRADO";

export interface CicloAvaliacao {
  id: string;
  ano: number;
  ciclo: 1 | 2 | 3;
  dataInicio?: string;
  dataFim?: string;
  status: StatusCicloAvaliacao;
  dataCriacao: string;
  dataUltimaAtualizacao: string;
  dataAtivacao?: string;
  dataEncerramento?: string;
}
