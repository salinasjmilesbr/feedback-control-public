/**
 * F6 — DESCOBERTA da avaliação do colaborador no ciclo: núcleo TESTÁVEL.
 *
 * Responsabilidade única: compor, com dependências INJETADAS, o estado da
 * descoberta e aplicar a regra pura `resolverDescobertaAvaliacao`.
 *
 * - `evaluation.create` é avaliado contra o COLABORADOR no ciclo (mesma
 *   resolução do CREATE: fotografia do ciclo + alcance do ator);
 * - `evaluation.write` e `evaluation.read` são avaliados contra a AVALIAÇÃO
 *   encontrada (ocorrência materializada vigente / relação de leitura).
 *
 * O módulo NÃO conhece Supabase nem Policy Engine: a fronteira confiável injeta
 * as três dependências. Nenhuma capability nova; nenhuma matrícula.
 */

export interface AvaliacaoEncontrada {
  readonly id: string;
  readonly status: string;
}

export interface EstadoDescoberta {
  /** `false` = ciclo inexistente no tenant do ator (cross-tenant ⇒ inexistente). */
  readonly cicloOk: boolean;
  /** Avaliação NÃO CANCELADA de (organização, ciclo, colaborador), ou `null`. */
  readonly encontrada: AvaliacaoEncontrada | null;
  readonly autorizaCriar: boolean;
  readonly autorizaEscrever: boolean;
  readonly autorizaLer: boolean;
}

export interface DepsEstadoDescoberta {
  /** O ciclo existe no tenant do ator? (revalidação server-side) */
  readonly cicloDoTenant: () => Promise<boolean>;
  /**
   * Avaliação NÃO CANCELADA de (organização, ciclo, colaborador). A unicidade é
   * garantida pelo índice parcial do banco; erro ⇒ `null` (fail-closed).
   */
  readonly avaliacaoNaoCancelada: () => Promise<AvaliacaoEncontrada | null>;
  /** Decisão do Policy Engine para a capability × alvo informados. */
  readonly autorizar: (
    capability: "evaluation.create" | "evaluation.write" | "evaluation.read",
    alvo: { readonly type: "evaluation" | "collaborator"; readonly id: string },
    collaboratorId: string
  ) => Promise<boolean>;
}

/**
 * Monta o estado da descoberta. Fail-closed: qualquer exceção das dependências
 * resulta em `cicloOk: false` / autorizações `false` — nunca em ALLOW.
 */
export async function carregarEstadoDescoberta(
  deps: DepsEstadoDescoberta,
  collaboratorId: string
): Promise<EstadoDescoberta> {
  const negado: EstadoDescoberta = {
    cicloOk: false,
    encontrada: null,
    autorizaCriar: false,
    autorizaEscrever: false,
    autorizaLer: false,
  };

  try {
    if (!(await deps.cicloDoTenant())) return negado;
  } catch {
    return negado;
  }

  let encontrada: AvaliacaoEncontrada | null;
  try {
    encontrada = await deps.avaliacaoNaoCancelada();
  } catch {
    return negado;
  }

  const decidir = async (
    capability: "evaluation.create" | "evaluation.write" | "evaluation.read",
    alvo: { readonly type: "evaluation" | "collaborator"; readonly id: string }
  ): Promise<boolean> => {
    try {
      return (await deps.autorizar(capability, alvo, collaboratorId)) === true;
    } catch {
      return false;
    }
  };

  const autorizaCriar = await decidir("evaluation.create", {
    type: "collaborator",
    id: collaboratorId,
  });

  // Os ramos de CONTEÚDO só existem quando há avaliação a acessar.
  const autorizaEscrever = encontrada
    ? await decidir("evaluation.write", { type: "evaluation", id: encontrada.id })
    : false;
  const autorizaLer = encontrada
    ? await decidir("evaluation.read", { type: "evaluation", id: encontrada.id })
    : false;

  return { cicloOk: true, encontrada, autorizaCriar, autorizaEscrever, autorizaLer };
}
