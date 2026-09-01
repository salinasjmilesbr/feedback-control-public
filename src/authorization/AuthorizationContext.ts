import type {
  FuncaoColaborador,
  StatusColaborador,
} from "../types/Colaborador";

export type AuthorizationActor = Readonly<{
  matricula: number;
  funcao?: FuncaoColaborador;
  status: StatusColaborador;
}>;

export type AuthorizationContext = Readonly<{
  actor: AuthorizationActor;
}>;
