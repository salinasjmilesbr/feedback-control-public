import type { Colaborador } from "../../types/Colaborador";

/** Cadastro por matrícula; não substitui autorização ou registro de movimentações. */
export interface CollaboratorRepository {
  getColaboradores(): Colaborador[];
  getColaboradorByMatricula(matricula: number): Colaborador | undefined;
  saveColaborador(colaborador: Colaborador): void;
  updateColaborador(colaborador: Colaborador): void;
}
