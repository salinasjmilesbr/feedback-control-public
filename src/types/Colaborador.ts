export type StatusColaborador =
  | "ATIVO"
  | "LICENCA"
  | "DESLIGADO";

export interface Colaborador {
  matricula: number;
  status: StatusColaborador;

  nome: string;
  email: string;
  cargo: string;
  area: string;
  respondePara: string;

  dataAdmissao?: string;
  dataInicioLicenca?: string;
  dataFimLicenca?: string;
  dataDesligamento?: string;
}