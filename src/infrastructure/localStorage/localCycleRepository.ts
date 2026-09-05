import type { CycleRepository } from "../../application/ports/CycleRepository";
import {
  criarCiclo,
  getCicloAtivo,
  getCiclosAvaliacao,
} from "../../services/cicloAvaliacaoStorage";

/** Adapter de transição: inicialização e validações permanecem no storage atual. */
export const localCycleRepository: CycleRepository = {
  getCiclosAvaliacao,
  getCicloAtivo,
  criarCiclo,
};
