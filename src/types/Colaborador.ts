export type StatusColaborador =
  | "ATIVO"
  | "LICENCA"
  | "DESLIGADO";

export type FuncaoColaborador =
  | "GERENTE"
  | "COORDENADOR"
  | "CONSULTOR"
  | "ANALISTA";

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
