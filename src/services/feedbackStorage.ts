import type { Colaborador } from "../types/Colaborador";
import type { Feedback } from "../types/Feedback";

const STORAGE_KEY = "feedback-control-feedbacks";

/**
 * F5-06 (Issue #103) — CUTOVER CONCLUÍDO: este módulo é SOMENTE LEITURA para o
 * legado.
 *
 * A partir do cutover de escrita, NENHUMA avaliação nova é criada, editada,
 * cancelada ou reaberta no `localStorage`. A autoridade de escrita é
 * exclusivamente do PostgreSQL, pelo caminho soberano:
 *
 *   tela → acessoAvaliacoesSoberanas → Edge Function → Policy Engine → RPC
 *
 * O que resta aqui:
 * - LEITURA do acervo legado (registros anteriores ao cutover), hoje usada pela
 *   apresentação administrativa/relatórios dos dados antigos;
 * - as regras de LEITURA derivadas do legado (unicidade, visibilidade e
 *   "avaliação vazia"); o cálculo oficial das avaliações novas é server-side
 *   (D13) e não vive aqui;
 * - a proibição explícita de qualquer escrita local (defesa em profundidade).
 *
 * Regras preservadas: sem dual-write; o legado NUNCA volta a ser autoridade
 * (rollback proibido após a primeira escrita exclusiva no banco, D12/§11.3) e
 * nenhum caminho faz fallback para o armazenamento local quando o backend falha.
 */

export function getFeedbacks(): Feedback[] {
  const data = localStorage.getItem(STORAGE_KEY);

  if (!data) {
    return [];
  }

  try {
    return JSON.parse(data) as Feedback[];
  } catch {
    return [];
  }
}

/**
 * Guarda de regressão: qualquer caminho que tente gravar avaliação no legado é
 * recusado de forma explícita. Exportada para que os testes possam provar que a
 * autoridade local foi efetivamente removida do produto.
 */
export function escreverNoLegadoEstaProibido(operacao: string): never {
  throw new Error(
    `A escrita de avaliações no armazenamento local foi desativada (${operacao}). ` +
      "Use o caminho soberano de avaliações (PostgreSQL)."
  );
}

export function getFeedbacksByColaborador(colaboradorId: number): Feedback[] {
  return getFeedbacks().filter(
    (feedback) => feedback.colaboradorId === colaboradorId
  );
}

export function existeAvaliacaoNaoCanceladaNoCiclo(
  feedbacks: Feedback[],
  colaboradorId: number,
  ano: number,
  ciclo: number
): boolean {
  return feedbacks.some(
    (feedback) =>
      feedback.colaboradorId === colaboradorId &&
      feedback.ano === ano &&
      feedback.ciclo === ciclo &&
      feedback.status !== "CANCELADA"
  );
}

export function avaliacaoEstaVaziaParaCleanupInterno(
  feedback: Feedback
): boolean {
  const competenciasVazias = feedback.competencias.every(
    (competencia) =>
      competencia.nota <= 0 && competencia.comentario.trim().length === 0
  );
  const criteriosVazios =
    feedback.criteriosDetalhados?.every(
      (criterio) =>
        criterio.nota <= 0 &&
        criterio.observacaoGerente.trim().length === 0 &&
        criterio.observacaoCoordenador.trim().length === 0 &&
        !criterio.observacaoGerenteAutorMatricula &&
        !criterio.observacaoGerenteAutorNome &&
        !criterio.observacaoGerenteData &&
        !criterio.observacaoCoordenadorAutorMatricula &&
        !criterio.observacaoCoordenadorAutorNome &&
        !criterio.observacaoCoordenadorData &&
        criterio.subcriterios.every(
          (subcriterio) =>
            subcriterio.notaGerente <= 0 &&
            subcriterio.notaCoordenador <= 0 &&
            subcriterio.notaColegiado <= 0 &&
            subcriterio.notaFinal <= 0 &&
            (subcriterio.votosColegiado?.length ?? 0) === 0 &&
            !subcriterio.avaliadorGerenteMatricula &&
            !subcriterio.avaliadorGerenteNome &&
            !subcriterio.dataAvaliacaoGerente &&
            !subcriterio.avaliadorCoordenadorMatricula &&
            !subcriterio.avaliadorCoordenadorNome &&
            !subcriterio.dataAvaliacaoCoordenador
        )
    ) ?? true;

  return (
    feedback.status === "RASCUNHO" &&
    feedback.notaMedia <= 0 &&
    competenciasVazias &&
    criteriosVazios &&
    !feedback.feedbackFinalGerente?.trim() &&
    !feedback.feedbackFinalGerenteAutorMatricula &&
    !feedback.feedbackFinalGerenteAutorNome &&
    !feedback.feedbackFinalGerenteData &&
    !feedback.feedbackFinalCoordenador?.trim() &&
    !feedback.feedbackFinalCoordenadorAutorMatricula &&
    !feedback.feedbackFinalCoordenadorAutorNome &&
    !feedback.feedbackFinalCoordenadorData &&
    !feedback.dataConclusao &&
    feedback.encerradaComPendencias !== true &&
    (feedback.pendenciasEncerramento?.length ?? 0) === 0
  );
}

/**
 * Cleanup de avaliação vazia criada automaticamente — DESATIVADO junto com a
 * autoridade local.
 *
 * A exclusão física de registros do acervo legado passa a ser fail-closed: o
 * acervo é somente leitura neste caminho (D12/§11.3). Remoção de histórico do
 * legado é responsabilidade da atividade de importação/limpeza, fora do escopo
 * da F5-06 (§1.3) — nunca um efeito colateral do produto.
 */
export function removerAvaliacaoVaziaNoCleanupInterno(
  feedbackId: string
): never {
  const feedbacks = getFeedbacks();
  const feedback = feedbacks.find((item) => item.id === feedbackId);

  if (!feedback) {
    throw new Error("Avaliação não encontrada para cleanup interno.");
  }
  if (!avaliacaoEstaVaziaParaCleanupInterno(feedback)) {
    throw new Error("O cleanup interno só pode remover avaliações vazias.");
  }

  escreverNoLegadoEstaProibido("cleanup de avaliação vazia");
}

/**
 * Edição de avaliação no legado — REMOVIDA. Toda edição passa a ser soberana
 * (`gravarNotasSoberanas`/`gravarObservacoesSoberanas`/
 * `gravarComentarioFinalSoberano`), com autorização do Policy Engine na
 * fronteira confiável. A função permanece como barreira explícita para que
 * qualquer regressão falhe alto em vez de gravar localmente.
 */
export function updateFeedback(
  updatedFeedback: Feedback,
  usuarioAtual?: Colaborador
): never {
  // Assinatura preservada para compatibilidade de chamada; os argumentos não
  // são usados porque a escrita local deixou de existir.
  void updatedFeedback;
  void usuarioAtual;
  return escreverNoLegadoEstaProibido("edição de avaliação");
}

export function getFeedbacksAdministrativosByColaborador(
  colaboradorId: number,
  incluirCanceladas = false
): Feedback[] {
  return getFeedbacksByColaborador(colaboradorId).filter(
    (feedback) => incluirCanceladas || feedback.status !== "CANCELADA"
  );
}

export function getFeedbacksConcluidosByColaborador(
  colaboradorId: number
): Feedback[] {
  return getFeedbacksByColaborador(colaboradorId).filter(
    (feedback) => feedback.status === "CONCLUIDA"
  );
}

/**
 * Cancelamento auditado no legado — REMOVIDO. O cancelamento é soberano
 * (`cancelarAvaliacaoSoberana`), com motivo e autoria resolvidos server-side e
 * evento na mesma transação (D7/D26).
 */
export function persistirCancelamentoAuditadoInterno(
  feedbackId: string,
  motivo: string,
  autor: Colaborador,
  dataCancelamento: string
): never {
  // Assinatura preservada; a escrita local deixou de existir.
  void feedbackId;
  void motivo;
  void autor;
  void dataCancelamento;
  return escreverNoLegadoEstaProibido("cancelamento de avaliação");
}

/**
 * Reabertura auditada no legado — REMOVIDA. A reabertura é soberana
 * (`reabrirAvaliacaoSoberana`), com motivo obrigatório, capability/scope
 * verificados server-side e histórico preservado (D7/D8/D26).
 */
export function persistirReaberturaAuditadaInterno(
  feedbackId: string,
  motivoInformado: string,
  autor: Colaborador,
  dataReabertura: string
): never {
  // Assinatura preservada; a escrita local deixou de existir.
  void feedbackId;
  void motivoInformado;
  void autor;
  void dataReabertura;
  return escreverNoLegadoEstaProibido("reabertura de avaliação");
}
