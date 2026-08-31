export type StatusColaborador =
  | "ATIVO"
  | "LICENCA"
  | "DESLIGADO";

export type FuncaoColaborador =
  | "GERENTE"
  | "COORDENADOR"
  | "CONSULTOR"
  | "ANALISTA"
  | "ESTAGIARIO";

export type SenioridadeColaborador =
  | "JUNIOR"
  | "PLENO"
  | "SENIOR";

export interface Colaborador {
  matricula: number;
  status: StatusColaborador;

  nome: string;
  email: string;
  cargo: string;
  area: string;

  funcao?: FuncaoColaborador;
  senioridade?: SenioridadeColaborador;
  gestorDiretoMatricula?: number;
  avaliadoresColegiadoMatriculas?: number[];

  // Campos temporários para compatibilidade durante a migração.
  respondePara: string;
  gerente?: string;

  dataAdmissao?: string;
  dataInicioLicenca?: string;
  dataFimLicenca?: string;
  dataDesligamento?: string;
}


/**
 * Funções avaliadas pela estrutura com gerente, coordenador direto e colegiado.
 * Estagiário segue o mesmo fluxo operacional de avaliação do Analista,
 * mas sem senioridade.
 */
export function funcaoUsaEstruturaAvaliacaoAnalista(
  funcao: FuncaoColaborador | undefined
): boolean {
  return funcao === "ANALISTA" || funcao === "ESTAGIARIO";
}
