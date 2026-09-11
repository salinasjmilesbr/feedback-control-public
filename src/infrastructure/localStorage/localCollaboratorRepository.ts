import type { CollaboratorRepository } from "../../application/ports/CollaboratorRepository";
import {
  getColaboradorByMatricula,
  getColaboradores,
  saveColaborador,
  updateColaborador,
} from "../../services/colaboradorStorage";

/**
 * Adapter LEGADO de `localStorage` — NÃO é o caminho de produção (F5-07).
 *
 * O port `CollaboratorRepository` passa a ser servido pela implementação
 * SOBERANA: `src/services/colaboradoresSoberanos/acessoColaboradoresSoberanos.ts`
 * sobre `src/infrastructure/supabase/colaboradores/repositorioColaboradores.ts`,
 * onde o `PostgreSQL` é a fonte de verdade.
 *
 * Este adapter existe apenas para o ambiente DEV/testes (fixtures sintéticas):
 *
 * - a LEITURA é pura (I7): não normaliza, não injeta gestores e não grava;
 * - `saveColaborador`/`updateColaborador` delegam às barreiras fail-closed de
 *   `colaboradorStorage` e sempre lançam — nenhuma escrita local é permitida.
 *
 * Nenhum consumidor de produção deve importá-lo; a única referência fora deste
 * arquivo é o teste `localCollaboratorRepository.test.ts`.
 */
export const localCollaboratorRepository: CollaboratorRepository = {
  getColaboradores,
  getColaboradorByMatricula,
  saveColaborador,
  updateColaborador,
};
