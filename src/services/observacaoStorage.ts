import type {
  Observacao,
  TipoObservacao,
} from "../types/Observacao";
import type { Colaborador } from "../types/Colaborador";
import {
  ordenarPorAnoECiclo,
  type OrdemPorCiclo,
} from "../utils/ordenacaoPorCiclo";

/**
 * F5-11 P5 (Issue #250) — ACERVO LEGADO de observações, agora **somente leitura**
 * e FORA do caminho funcional.
 *
 * A autoridade de observações é soberana: `src/application/ports/ObservationRepository`
 * → `src/infrastructure/supabase/observacoes/repositorioObservacoesSoberanas`
 * (adapter fail-closed) → Edge `observacoes` → RPCs `observacao_*` (capability +
 * escopo + relação + autoria + estado no Postgres).
 *
 * Regras preservadas nesta fase:
 * - **D13 — sem migração:** os dados que já estavam neste acervo local NÃO são
 *   migrados nem lidos para decidir nada; após a barreira eles ficam invisíveis.
 * - **Sem dual-read/dual-write:** nenhuma leitura daqui alimenta o caminho
 *   funcional e nenhuma falha soberana cai para este armazenamento.
 * - **Escrita proibida:** as três mutações LANÇAM (barreira de fase). O ciclo
 *   local deixa de decidir autorização (o gate de ciclo é do servidor: D12).
 */
const STORAGE_KEY = "feedback-control-observacoes";

/**
 * Mensagem pública da barreira de escrita local (D13). Explícita quanto à
 * substituição (gravação soberana) e quanto à ausência de migração.
 */
export const ERRO_ESCRITA_LOCAL_OBSERVACOES =
  "A gravação local de observações foi desativada (F5-11 P5): a escrita é feita pelo repositório soberano de observações (Edge `observacoes` → RPC `observacao_*`). Os dados locais NÃO são migrados (D13) e não há fallback local.";

/** Barreira única de escrita: nenhuma mutação local é permitida nesta fase. */
function barreiraDeEscritaLocal(): never {
  throw new Error(ERRO_ESCRITA_LOCAL_OBSERVACOES);
}

function getTodasObservacoes(): Observacao[] {
  const data = localStorage.getItem(STORAGE_KEY);

  if (!data) return [];

  try {
    return JSON.parse(data) as Observacao[];
  } catch {
    return [];
  }
}

export function getObservacoesByColaborador(
  colaboradorMatricula: number,
  incluirExcluidas = false,
  ordem: OrdemPorCiclo = "RECENTES"
): Observacao[] {
  const observacoes = getTodasObservacoes().filter(
    (observacao) =>
      observacao.colaboradorMatricula === colaboradorMatricula &&
      (incluirExcluidas || !observacao.excluida)
  );

  return ordenarPorAnoECiclo(
    observacoes,
    ordem,
    (observacao) => observacao.dataCriacao
  );
}

export function getObservacoesComunicadasByColaborador(
  colaboradorMatricula: number
): Observacao[] {
  return getObservacoesByColaborador(colaboradorMatricula).filter(
    (observacao) => observacao.comunicado
  );
}

export function getObservacoesComunicadasByCiclo(
  colaboradorMatricula: number,
  ano: number,
  ciclo: 1 | 2 | 3
): Observacao[] {
  return getObservacoesComunicadasByColaborador(
    colaboradorMatricula
  ).filter(
    (observacao) =>
      observacao.ano === ano &&
      observacao.ciclo === ciclo
  );
}

export function getObservacoesByCiclo(
  ano: number,
  ciclo: 1 | 2 | 3,
  incluirExcluidas = false
): Observacao[] {
  return ordenarPorAnoECiclo(
    getTodasObservacoes().filter(
      (observacao) =>
        observacao.ano === ano &&
        observacao.ciclo === ciclo &&
        (incluirExcluidas || !observacao.excluida)
    ),
    "RECENTES",
    (observacao) => observacao.dataCriacao
  );
}

/**
 * BARREIRA (D13): criação local desativada. A assinatura é preservada apenas
 * para compatibilidade de chamada durante o cutover — os parâmetros são inertes
 * por desenho (identidade, tenant, autoria, ciclo e id agora são soberanos).
 */
export function criarObservacao(
  colaboradorMatricula: number,
  tipo: TipoObservacao,
  texto: string,
  comunicado: boolean,
  ano: number,
  ciclo: 1 | 2 | 3,
  autor: Colaborador
): never {
  void [colaboradorMatricula, tipo, texto, comunicado, ano, ciclo, autor];
  return barreiraDeEscritaLocal();
}

/**
 * BARREIRA (D13): edição local desativada (mesma preservação de assinatura).
 */
export function atualizarObservacao(
  id: string,
  tipo: TipoObservacao,
  texto: string,
  comunicado: boolean,
  ano: number,
  ciclo: 1 | 2 | 3,
  autor: Colaborador
): never {
  void [id, tipo, texto, comunicado, ano, ciclo, autor];
  return barreiraDeEscritaLocal();
}

/**
 * BARREIRA (D13): exclusão local desativada (mesma preservação de assinatura).
 */
export function excluirObservacao(
  id: string,
  autor: Colaborador
): never {
  void [id, autor];
  return barreiraDeEscritaLocal();
}
