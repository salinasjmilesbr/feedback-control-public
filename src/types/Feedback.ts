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
  notaCoordenador: number;
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
  observacaoCoordenador: string;
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

  ano: number;
  ciclo: 1 | 2 | 3;

  competencias: FeedbackCompetencia[];

  notaMedia: number;

  criteriosDetalhados?: FeedbackCriterioDetalhado[];
  feedbackFinalGerente?: string;
  feedbackFinalCoordenador?: string;
  
}
