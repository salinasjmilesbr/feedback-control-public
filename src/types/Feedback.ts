export interface FeedbackCompetencia {
  competenciaId: string;
  competenciaNome: string;
  nota: number;
  comentario: string;
}

export interface VotoColegiado {
  avaliadorMatricula: number;
  avaliadorNome: string;
  nota: number;
  dataAtualizacao?: string;
}

export interface FeedbackSubcriterioDetalhado {
  nome: string;
  notaGerente: number;
  avaliadorGerenteMatricula?: number;
  avaliadorGerenteNome?: string;
  dataAvaliacaoGerente?: string;
  notaCoordenador: number;
  avaliadorCoordenadorMatricula?: number;
  avaliadorCoordenadorNome?: string;
  dataAvaliacaoCoordenador?: string;
  notaColegiado: number;
  votosColegiado?: VotoColegiado[];
  notaFinal: number;
}

export interface FeedbackCriterioDetalhado {
  criterioId: string;
  criterioNome: string;
  nota: number;
  subcriterios: FeedbackSubcriterioDetalhado[];
  observacaoGerente: string;
  observacaoGerenteAutorMatricula?: number;
  observacaoGerenteAutorNome?: string;
  observacaoGerenteData?: string;
  observacaoCoordenador: string;
  observacaoCoordenadorAutorMatricula?: number;
  observacaoCoordenadorAutorNome?: string;
  observacaoCoordenadorData?: string;
}

export type StatusFeedback =
  | "RASCUNHO"
  | "PRONTA_PARA_FEEDBACK"
  | "CONCLUIDA";

export interface Feedback {
  id: string;
  colaboradorId: number;
  colaboradorNome: string;

  status: StatusFeedback;

  data: string;

  dataCriacao?: string;
  dataUltimaAtualizacao?: string;
  dataConclusao?: string;

  ano: number;
  ciclo: 1 | 2 | 3;

  competencias: FeedbackCompetencia[];

  notaMedia: number;

  criteriosDetalhados?: FeedbackCriterioDetalhado[];
  feedbackFinalGerente?: string;
  feedbackFinalGerenteAutorMatricula?: number;
  feedbackFinalGerenteAutorNome?: string;
  feedbackFinalGerenteData?: string;
  feedbackFinalCoordenador?: string;
  feedbackFinalCoordenadorAutorMatricula?: number;
  feedbackFinalCoordenadorAutorNome?: string;
  feedbackFinalCoordenadorData?: string;
  encerradaComPendencias?: boolean;
  pendenciasEncerramento?: string[];
  
}
