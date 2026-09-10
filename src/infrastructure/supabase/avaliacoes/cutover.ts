/**
 * F5-06 (Issue #103) — marca de CUTOVER do domínio de avaliações (D12/§11).
 *
 * A partir do cutover de escrita, Supabase é a fonte de verdade das avaliações
 * NOVAS. O `localStorage` permanece apenas como legado de LEITURA dos registros
 * anteriores (`colaboradorId` = matrícula, criados antes do corte) e:
 * - NÃO recebe espelho (sem dual-write);
 * - NÃO é fallback autoritativo;
 * - NÃO volta a ser autoridade depois da primeira escrita exclusiva no banco.
 *
 * A marca é apenas um INSTANTE de corte (informação de migração): não é
 * autorização, não é tenancy e não é grant. Nenhum componente pode usá-la para
 * decidir autorização — quem decide é o Policy Engine na fronteira confiável.
 */

/** Instante do cutover de escrita (ISO-8601, UTC). */
export const INSTANTE_CUTOVER_AVALIACOES = "2026-01-01T00:00:00.000Z";

export type OrigemAvaliacao = "POSTGRES" | "LEGADO_LOCAL";

function instante(valor: unknown): number | null {
  if (typeof valor !== "string" || valor.trim() === "") return null;
  const tempo = Date.parse(valor);
  return Number.isFinite(tempo) ? tempo : null;
}

/**
 * Classifica um registro legado (`Feedback`) pela data de criação:
 * criado a partir do corte ⇒ caminho novo (PostgreSQL); antes ⇒ legado.
 *
 * Fail-closed: registro SEM data de criação é tratado como LEGADO (não ingressa
 * no caminho novo por omissão).
 */
export function origemDoRegistroLegado(entrada: {
  readonly dataCriacao?: string | null;
}): OrigemAvaliacao {
  const criadoEm = instante(entrada.dataCriacao);
  const corte = instante(INSTANTE_CUTOVER_AVALIACOES);
  if (criadoEm === null || corte === null) return "LEGADO_LOCAL";
  return criadoEm >= corte ? "POSTGRES" : "LEGADO_LOCAL";
}

/**
 * Separa o acervo legado do caminho novo SEM misturar autoridades: devolve o
 * legado (somente leitura) e sinaliza quantos registros foram cortados. Nunca
 * converte, nunca espelha e nunca escreve no destino.
 */
export function separarAcervoLegado<T extends { readonly dataCriacao?: string | null }>(
  registros: readonly T[]
): { readonly legado: readonly T[]; readonly aposCorte: readonly T[] } {
  const legado: T[] = [];
  const aposCorte: T[] = [];
  for (const registro of registros) {
    if (origemDoRegistroLegado(registro) === "LEGADO_LOCAL") legado.push(registro);
    else aposCorte.push(registro);
  }
  return { legado, aposCorte };
}
