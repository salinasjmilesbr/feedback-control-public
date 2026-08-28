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
  | "EXCLUSAO"
  | "APROVACAO_COORDENADOR"
  | "APROVACAO_GERENTE"
  | "INVALIDACAO_APROVACOES";

export interface AprovacaoMeta {
  matricula: number;
  nome: string;
  data: string;
}

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

  // Aprovação formal da meta. Campos opcionais preservam compatibilidade
  // com registros criados antes desta funcionalidade.
  aprovacaoCoordenador?: AprovacaoMeta;
  aprovacaoGerente?: AprovacaoMeta;

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
