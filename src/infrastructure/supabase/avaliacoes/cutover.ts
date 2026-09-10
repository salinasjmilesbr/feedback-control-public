/**
 * F5-06 (Issue #103) — LIVRO-CAIXA DE CUTOVER (cliente).
 *
 * Este módulo responde a UMA pergunta: **o cliente sabe, por evidência de uma
 * escrita server-side CONFIRMADA, que esta avaliação existe exclusivamente no
 * PostgreSQL?**
 *
 * ## O que este arquivo É e o que NÃO é
 *
 * - É um registro local de ROTEAMENTO/NAVEGAÇÃO: diz à tela "use o caminho
 *   soberano para este id" e permite alcançar avaliações novas que nunca
 *   existirão no `localStorage` legado.
 * - **NÃO é autorização** — quem decide ALLOW/DENY é o Policy Engine na
 *   fronteira confiável, a cada operação.
 * - **NÃO é tenancy** — o tenant vem sempre do recurso/da membership validados
 *   server-side.
 * - **NÃO é prova de existência** — a existência real é confirmada pelo
 *   PostgreSQL; a leitura soberana pode recusar (fail-closed) um id que conste
 *   aqui.
 *
 * ## Como a origem é decidida (nunca por data)
 *
 * Uma DATA não é evidência de nada: um registro local criado depois de qualquer
 * "instante de cutover" continuaria sendo local. A classificação é ESTRUTURAL:
 *
 *   1. a marca `POSTGRES` só existe quando o id veio de uma escrita server-side
 *      CONFIRMADA (UUID devolvido pela RPC e validado);
 *   2. **formato de UUID NÃO é evidência suficiente**: um id legado que por
 *      acaso tenha forma de UUID continua `LEGADO_LOCAL` enquanto não houver
 *      registro explícito de cutover (fail-closed);
 *   3. registro ausente, corrompido ou ilegível ⇒ `LEGADO_LOCAL` (nunca promove
 *      por omissão).
 *
 * ## Índices de NAVEGAÇÃO
 *
 * `CHAVE_CICLO_AVALIACOES` guarda dois índices, ambos apenas de navegação:
 * - `ids`: ano+número do ciclo → ids técnicos;
 * - `porColaborador`: ano+número+matrícula → id técnico (permite à tela saber
 *   que já existe avaliação nova de um colaborador no ciclo sem varrer o
 *   `localStorage` legado, que nunca a contém).
 *
 * A autoridade de unicidade continua sendo o índice único parcial do banco
 * (`uq_evaluations_org_cycle_collaborator_nao_cancelada`).
 */

/** Formato canônico de UUID (id técnico devolvido pelo PostgreSQL). */
const FORMATO_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** `true` somente para id técnico (UUID) — formato, NÃO evidência por si só. */
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

/**
 * Lê o conjunto de avaliações já confirmadas no PostgreSQL (ids técnicos).
 * Registro ausente, corrompido ou com forma inesperada ⇒ conjunto VAZIO
 * (fail-closed: nada é promovido por omissão).
 */
export function lerAvaliacoesCortadas(
  registroCutover: ArmazenamentoCutover | null = armazenamentoPadrao()
): ReadonlySet<string> {
  if (!registroCutover) return new Set();
  const bruto = registroCutover.getItem(CHAVE_AVALIACOES_CORTADAS);
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
  registroCutover: ArmazenamentoCutover | null = armazenamentoPadrao()
): MarcadorOrigem {
  if (!ehIdTecnicoPostgres(evaluationId)) {
    // Sem evidência do caminho novo: permanece legado (somente leitura).
    return { origem: "LEGADO_LOCAL", evaluationId: null };
  }

  const id = evaluationId.trim();
  if (registroCutover) {
    const atuais = lerAvaliacoesCortadas(registroCutover);
    if (!atuais.has(id)) {
      registroCutover.setItem(CHAVE_AVALIACOES_CORTADAS, JSON.stringify([...atuais, id]));
    }
  }
  return { origem: "POSTGRES", evaluationId: id };
}

/**
 * A avaliação possui EVIDÊNCIA REGISTRADA de escrita exclusiva no banco?
 *
 * Exige as DUAS coisas: id técnico (formato) **e** registro explícito do
 * cutover. Formato de UUID sozinho NÃO promove um registro a `POSTGRES` — um id
 * legado que por acaso tenha forma de UUID continua legado (fail-closed).
 *
 * Quando `true`, NENHUM caminho local pode voltar a ser autoridade para ela
 * (sem dual-write).
 */
export function avaliacaoVinculadaAoBanco(
  evaluationId: string,
  registroCutover: ArmazenamentoCutover | null = armazenamentoPadrao()
): boolean {
  if (!ehIdTecnicoPostgres(evaluationId)) return false;
  return lerAvaliacoesCortadas(registroCutover).has(evaluationId.trim());
}

// ---------------------------------------------------------------------------
// Índices de NAVEGAÇÃO (nunca autoridade)
// ---------------------------------------------------------------------------

/** Chave local dos índices de navegação do ciclo. */
export const CHAVE_CICLO_AVALIACOES = "feedback-control-ciclo-avaliacoes-postgres";

interface IndiceNavegacao {
  /** namespace de cache → ids técnicos conhecidos. */
  readonly ids?: Record<string, readonly string[]>;
  /** namespace de cache → id técnico conhecido por colaborador. */
  readonly porColaborador?: Record<string, string>;
}

/**
 * Chave canônica do índice por ciclo. A organização entra apenas como
 * NAMESPACE DE CACHE/NAVEGAÇÃO: NÃO é prova de tenant nem autorização — toda
 * operação real revalida o tenant server-side. Ela existe para que a mesma
 * matrícula/ano/ciclo em organizações diferentes não colida no navegador.
 */
export function chaveAnoCiclo(
  organizationId: string,
  ano: number,
  ciclo: number
): string {
  return `${organizationId}|${ano}-${ciclo}`;
}

/** Chave canônica do índice por colaborador dentro de um ciclo (por tenant). */
export function chaveCicloColaborador(
  organizationId: string,
  ano: number,
  ciclo: number,
  matricula: number
): string {
  return `${organizationId}|${ano}-${ciclo}-${matricula}`;
}

function lerIndice(
  registroCutover: ArmazenamentoCutover
): Required<IndiceNavegacao> {
  const bruto = registroCutover.getItem(CHAVE_CICLO_AVALIACOES);
  if (!bruto) return { ids: {}, porColaborador: {} };
  try {
    const dados = JSON.parse(bruto);
    if (typeof dados !== "object" || dados === null || Array.isArray(dados)) {
      return { ids: {}, porColaborador: {} };
    }
    const cru = dados as IndiceNavegacao;
    const ids: Record<string, string[]> = {};
    for (const [chave, valor] of Object.entries(cru.ids ?? {})) {
      if (!Array.isArray(valor)) continue;
      const validos = valor.filter((item): item is string => ehIdTecnicoPostgres(item));
      if (validos.length > 0) ids[chave] = validos;
    }
    const porColaborador: Record<string, string> = {};
    for (const [chave, valor] of Object.entries(cru.porColaborador ?? {})) {
      if (ehIdTecnicoPostgres(valor)) porColaborador[chave] = valor.trim();
    }
    return { ids, porColaborador };
  } catch {
    return { ids: {}, porColaborador: {} };
  }
}

function gravarIndice(
  registroCutover: ArmazenamentoCutover,
  indice: Required<IndiceNavegacao>
): void {
  registroCutover.setItem(
    CHAVE_CICLO_AVALIACOES,
    JSON.stringify({ ids: indice.ids, porColaborador: indice.porColaborador })
  );
}

/**
 * Associa ids soberanos ao ciclo (organização + ano + número) e, quando
 * `matriculaAvaliado` é informada, registra também o índice por colaborador.
 *
 * CACHE DE NAVEGAÇÃO opcional: só registra id técnico válido, é idempotente e
 * NADA aqui estabelece existência, tenant ou autorização. A ausência deste
 * registro não impede descobrir a avaliação (a resolução soberana consulta o
 * banco de qualquer forma).
 */
export function registrarAvaliacoesDoCiclo(
  organizationId: string,
  ano: number,
  ciclo: number,
  evaluationIds: readonly unknown[],
  registroCutover: ArmazenamentoCutover | null = armazenamentoPadrao(),
  matriculaAvaliado?: number
): readonly string[] {
  const novos = evaluationIds
    .filter((id): id is string => ehIdTecnicoPostgres(id))
    .map((id) => id.trim());
  if (!registroCutover || novos.length === 0) return novos;

  const chave = chaveAnoCiclo(organizationId, ano, ciclo);
  const indice = lerIndice(registroCutover);
  const atuais = new Set(indice.ids[chave] ?? []);
  for (const id of novos) atuais.add(id);
  indice.ids[chave] = Array.from(atuais);

  if (matriculaAvaliado !== undefined && Number.isFinite(matriculaAvaliado)) {
    // Uma avaliação nova por (ciclo, colaborador): o mais recente prevalece.
    indice.porColaborador[
      chaveCicloColaborador(organizationId, ano, ciclo, matriculaAvaliado)
    ] = novos[novos.length - 1]!;
  }

  gravarIndice(registroCutover, indice);
  return indice.ids[chave]!;
}

/** Ids soberanos JÁ CONHECIDOS de um ciclo (cache). Nunca inclui legado. */
export function lerAvaliacoesDoCiclo(
  organizationId: string,
  ano: number,
  ciclo: number,
  registroCutover: ArmazenamentoCutover | null = armazenamentoPadrao()
): readonly string[] {
  if (!registroCutover) return [];
  return lerIndice(registroCutover).ids[chaveAnoCiclo(organizationId, ano, ciclo)] ?? [];
}

/**
 * Id soberano JÁ CONHECIDO (cache) da avaliação nova de um colaborador no ciclo,
 * ou `null`.
 *
 * É apenas atalho de navegação, no namespace da organização. Um resultado
 * `null` NÃO significa que a avaliação não existe: a descoberta real é feita
 * contra o banco (`resolverLeituraAvaliacao`).
 */
export function lerAvaliacaoNovaDoColaboradorNoCiclo(
  organizationId: string,
  ano: number,
  ciclo: number,
  matricula: number,
  registroCutover: ArmazenamentoCutover | null = armazenamentoPadrao()
): string | null {
  if (!registroCutover) return null;
  return (
    lerIndice(registroCutover).porColaborador[
      chaveCicloColaborador(organizationId, ano, ciclo, matricula)
    ] ?? null
  );
}

/**
 * Remove uma entrada OBSOLETA do cache de navegação (ex.: a avaliação apontada
 * não existe mais / foi recusada pelo servidor). Não afeta a evidência de
 * cutover (`CHAVE_AVALIACOES_CORTADAS`), que é append-only.
 */
export function esquecerAvaliacaoNovaDoColaboradorNoCiclo(
  organizationId: string,
  ano: number,
  ciclo: number,
  matricula: number,
  registroCutover: ArmazenamentoCutover | null = armazenamentoPadrao()
): void {
  if (!registroCutover) return;
  const indice = lerIndice(registroCutover);
  const chave = chaveCicloColaborador(organizationId, ano, ciclo, matricula);
  if (!(chave in indice.porColaborador)) return;
  delete indice.porColaborador[chave];
  gravarIndice(registroCutover, indice);
}
