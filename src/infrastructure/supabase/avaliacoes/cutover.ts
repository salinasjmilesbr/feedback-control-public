/**
 * F5-06 (Issue #103) — CUTOVER do domínio de avaliações (D12/§11).
 *
 * A partir do cutover de escrita, Supabase é a fonte de verdade das avaliações
 * NOVAS. O `localStorage` permanece apenas como legado de LEITURA e:
 * - NÃO recebe espelho (sem dual-write);
 * - NÃO é fallback autoritativo;
 * - NÃO volta a ser autoridade depois da primeira escrita exclusiva no banco.
 *
 * ## Como a origem é decidida (correção pós-auditoria)
 *
 * A origem NÃO é inferida por DATA. Uma data (mesmo um "instante de cutover"
 * fixo no código) não é evidência de nada: registros locais podem ser criados
 * depois de qualquer data escolhida e seriam classificados como banco
 * indevidamente. A classificação é ESTRUTURAL, a partir de evidência do caminho
 * novo:
 *
 *   1. a marca `POSTGRES` só existe quando o id veio de uma escrita server-side
 *      CONFIRMADA (UUID retornado pela RPC e validado);
 *   2. qualquer registro sem essa evidência é `LEGADO_LOCAL` e permanece
 *      SOMENTE LEITURA — inclusive registros recentes, sem data ou com data
 *      inválida (fail-closed).
 *
 * A marca local é apenas livro-caixa de migração: nunca concede autorização,
 * nunca é tenancy e nunca é prova de existência no banco (a fonte soberana
 * continua sendo o PostgreSQL, consultado pela fronteira confiável).
 */

/** Formato canônico de UUID (id técnico devolvido pelo PostgreSQL). */
const FORMATO_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** `true` somente para id técnico (UUID) — evidência do caminho novo. */
export function ehIdTecnicoPostgres(valor: unknown): valor is string {
  return typeof valor === "string" && FORMATO_UUID.test(valor.trim());
}

export type OrigemAvaliacao = "POSTGRES" | "LEGADO_LOCAL";

/**
 * Marcador de origem de um registro. `POSTGRES` só é válido com id técnico
 * (UUID) de escrita confirmada; qualquer outra combinação é legado local.
 */
export type MarcadorOrigem =
  | { readonly origem: "POSTGRES"; readonly evaluationId: string }
  | { readonly origem: "LEGADO_LOCAL"; readonly evaluationId?: string | null };

/** Chave local do REGISTRO de cutover (livro-caixa; não é autoridade). */
export const CHAVE_AVALIACOES_CORTADAS = "feedback-control-avaliacoes-no-postgres";

/** Porta mínima de armazenamento (permite teste sem DOM). */
export interface ArmazenamentoCutover {
  getItem(chave: string): string | null;
  setItem(chave: string, valor: string): void;
}

/** Implementação em memória — usada quando não há `localStorage` (SSR/teste). */
export function criarArmazenamentoMemoria(): ArmazenamentoCutover {
  const dados = new Map<string, string>();
  return {
    getItem: (chave) => dados.get(chave) ?? null,
    setItem: (chave, valor) => {
      dados.set(chave, valor);
    },
  };
}

function armazenamentoPadrao(): ArmazenamentoCutover | null {
  if (typeof localStorage === "undefined") return null;
  return {
    getItem: (chave) => localStorage.getItem(chave),
    setItem: (chave, valor) => localStorage.setItem(chave, valor),
  };
}

/**
 * Classifica um marcador. Um marcador `POSTGRES` só é aceito com id técnico
 * válido; sem essa evidência o resultado é `LEGADO_LOCAL` (fail-closed).
 */
export function origemDoMarcador(
  marcador: MarcadorOrigem | null | undefined
): OrigemAvaliacao {
  if (!marcador || marcador.origem !== "POSTGRES") return "LEGADO_LOCAL";
  return ehIdTecnicoPostgres(marcador.evaluationId) ? "POSTGRES" : "LEGADO_LOCAL";
}

/**
 * Separa o acervo em registros do PostgreSQL (com evidência estrutural) e
 * legado local (somente leitura). NENHUMA heurística de data é aplicada: o que
 * não tem marcador explícito do caminho novo é legado.
 */
export function separarAcervoLegado<T>(
  registros: readonly T[],
  obterMarcador: (registro: T) => MarcadorOrigem | null | undefined
): { readonly legado: readonly T[]; readonly postgres: readonly T[] } {
  const legado: T[] = [];
  const postgres: T[] = [];
  for (const registro of registros) {
    if (origemDoMarcador(obterMarcador(registro)) === "POSTGRES") postgres.push(registro);
    else legado.push(registro);
  }
  return { legado, postgres };
}

/** Lê o conjunto de avaliações já confirmadas no PostgreSQL (ids técnicos). */
export function lerAvaliacoesCortadas(
  armazenamento: ArmazenamentoCutover | null = armazenamentoPadrao()
): ReadonlySet<string> {
  if (!armazenamento) return new Set();
  const bruto = armazenamento.getItem(CHAVE_AVALIACOES_CORTADAS);
  if (!bruto) return new Set();
  try {
    const lista = JSON.parse(bruto);
    if (!Array.isArray(lista)) return new Set();
    // Somente ids técnicos válidos contam como evidência do caminho novo.
    return new Set(lista.filter((item): item is string => ehIdTecnicoPostgres(item)));
  } catch {
    return new Set();
  }
}

/**
 * Registra que uma avaliação passou a existir EXCLUSIVAMENTE no PostgreSQL.
 * Só marca com id técnico válido (UUID da escrita confirmada) e devolve o
 * marcador, para que o chamador use a MESMA evidência.
 *
 * A partir daqui o `localStorage` não é mais autoridade para ela (D12/§11.3):
 * rollback para o legado é proibido e correções são fix-forward.
 */
export function registrarAvaliacaoCortada(
  evaluationId: unknown,
  armazenamento: ArmazenamentoCutover | null = armazenamentoPadrao()
): MarcadorOrigem {
  if (!ehIdTecnicoPostgres(evaluationId)) {
    // Sem evidência do caminho novo: permanece legado (somente leitura).
    return { origem: "LEGADO_LOCAL", evaluationId: null };
  }

  const id = evaluationId.trim();
  if (armazenamento) {
    const atuais = lerAvaliacoesCortadas(armazenamento);
    if (!atuais.has(id)) {
      armazenamento.setItem(CHAVE_AVALIACOES_CORTADAS, JSON.stringify([...atuais, id]));
    }
  }
  return { origem: "POSTGRES", evaluationId: id };
}

/**
 * A avaliação possui evidência de escrita exclusiva no banco? Quando `true`,
 * NENHUM caminho local pode voltar a ser autoridade para ela (sem dual-write).
 */
export function avaliacaoVinculadaAoBanco(
  evaluationId: string,
  armazenamento: ArmazenamentoCutover | null = armazenamentoPadrao()
): boolean {
  if (!ehIdTecnicoPostgres(evaluationId)) return false;
  return lerAvaliacoesCortadas(armazenamento).has(evaluationId.trim());
}
