import type {
  FuncaoColaborador,
  SenioridadeColaborador,
  StatusColaborador,
} from "./Colaborador";

export type TipoMovimentacaoOrganizacional =
  | "ADMISSAO"
  | "ALTERACAO_ESTRUTURA"
  | "LICENCA"
  | "RETORNO_LICENCA"
  | "DESLIGAMENTO";

export type EscopoMovimentacaoOrganizacional =
  | "CICLO_ATUAL_E_POSTERIORES"
  | "SOMENTE_CICLOS_POSTERIORES";

export interface SnapshotOrganizacional {
  status: StatusColaborador;
  cargo: string;
  area: string;
  funcao?: FuncaoColaborador;
  senioridade?: SenioridadeColaborador;
  gestorDiretoMatricula?: number;
  gestorDiretoNome?: string;
  avaliadoresColegiadoMatriculas: number[];
  avaliadoresColegiadoNomes: string[];
}

export interface MovimentacaoOrganizacional {
  id: string;
  colaboradorMatricula: number;
  colaboradorNome: string;
  tipo: TipoMovimentacaoOrganizacional;
  dataVigencia: string;
  dataRegistro: string;
  escopo: EscopoMovimentacaoOrganizacional;
  cicloIdReferencia?: string;
  cicloReferenciaLabel?: string;
  motivo?: string;
  anterior?: SnapshotOrganizacional;
  atual: SnapshotOrganizacional;
  autorMatricula?: number;
  autorNome?: string;
}
