/**
 * F5-07 (I7) — LEITURA LEGADA SEM EFEITO COLATERAL; ESCRITA SOBERANA.
 *
 * `PostgreSQL` é a fonte soberana do cadastro de colaboradores
 * (`collaborators` + `collaborator_identifiers`). Este módulo é LEGADO e
 * permanece apenas como LEITURA para as telas ainda não migradas para a porta
 * única `src/services/colaboradoresSoberanos/acessoColaboradoresSoberanos.ts`:
 *
 * - `getColaboradores` / `getColaboradorByMatricula` apenas LEEM o que existe
 *   na chave local; NÃO gravam, NÃO migram/normalizam registros e NÃO injetam
 *   gestores sintéticos. O seed de `src/data/colaboradores` é usado como
 *   fixture de DEV somente quando a chave não existe — e não é regravado;
 * - `saveColaborador` / `updateColaborador` são BARREIRAS fail-closed: lançam
 *   erro explícito, porque a escrita de colaborador é soberana no PostgreSQL.
 */
import { colaboradores as colaboradoresIniciais } from "../data/colaboradores";
import type { Colaborador } from "../types/Colaborador";

const STORAGE_KEY = "feedback-control-colaboradores";

/**
 * Mensagem única das barreiras de escrita (F5-07/I7). O cadastro é soberano no
 * `PostgreSQL`; nenhuma mutação de colaborador passa por `localStorage`.
 */
export const ERRO_ESCRITA_COLABORADOR_SOBERANA =
  "A escrita de colaborador é soberana no PostgreSQL (F5-07): use a porta única " +
  "src/services/colaboradoresSoberanos/acessoColaboradoresSoberanos.ts. " +
  "O localStorage não é fonte de verdade do cadastro e não deve ser gravado.";

/** Leitura pura: devolve a base existente sem normalizar nem persistir. */
function lerBaseLegada(): Colaborador[] {
  const data = localStorage.getItem(STORAGE_KEY);

  // Fixture de DEV: chave ausente cai no seed sintético do repositório, sem
  // regravá-lo (I7 — a leitura nunca escreve).
  if (!data) return [...colaboradoresIniciais];

  return JSON.parse(data) as Colaborador[];
}

export function getColaboradores(): Colaborador[] {
  return lerBaseLegada();
}

export function getColaboradorByMatricula(
  matricula: number
): Colaborador | undefined {
  return getColaboradores().find(
    (colaborador) => colaborador.matricula === matricula
  );
}

export function saveColaborador(colaborador: Colaborador): void {
  throw new Error(
    `${ERRO_ESCRITA_COLABORADOR_SOBERANA} A matrícula ${colaborador.matricula} não foi gravada localmente.`
  );
}

export function updateColaborador(updatedColaborador: Colaborador): void {
  throw new Error(
    `${ERRO_ESCRITA_COLABORADOR_SOBERANA} A matrícula ${updatedColaborador.matricula} não foi atualizada localmente.`
  );
}
