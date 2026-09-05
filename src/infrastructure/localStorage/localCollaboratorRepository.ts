import type { CollaboratorRepository } from "../../application/ports/CollaboratorRepository";
import {
  getColaboradorByMatricula,
  getColaboradores,
  saveColaborador,
  updateColaborador,
} from "../../services/colaboradorStorage";

/** Adapter de transição: migrações e validações permanecem no storage atual. */
export const localCollaboratorRepository: CollaboratorRepository = {
  getColaboradores,
  getColaboradorByMatricula,
  saveColaborador,
  updateColaborador,
};
