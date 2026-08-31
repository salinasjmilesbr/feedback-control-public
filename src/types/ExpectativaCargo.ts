export type CargoExpectativa =
  | "ESTAGIARIO"
  | "ANALISTA_JUNIOR"
  | "ANALISTA_PLENO"
  | "ANALISTA_SENIOR"
  | "CONSULTOR"
  | "COORDENADOR";

export interface ExpectativaCargo {
  cargo: CargoExpectativa;
  nome: string;
  autonomia: string;
  tarefas: string;
  responsabilidades: string;
  foco: string;
}

export type ExpectativasCargo = ExpectativaCargo[];
