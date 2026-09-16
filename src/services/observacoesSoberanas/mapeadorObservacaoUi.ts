/**
 * F5-11 P5 (Issue #250), L2/L3 — MAPEADOR de projeção soberana → view-model de UI.
 *
 * ## O ponto sensível (e como ele NÃO é resolvido aqui)
 *
 * O tipo legado de UI (`src/types/Observacao.ts`) carrega IDENTIDADE POR
 * MATRÍCULA (`colaboradorMatricula`/`autorMatricula`, ambos `number` obrigatórios)
 * e histórico com autor por matrícula. A projeção soberana NÃO tem matrícula: ela
 * tem UUID (`collaborator_id`, `author_collaborator_id`). Converter UUID →
 * matrícula aqui exigiria uma tabela de identidade local — exatamente a
 * autoridade local que o cutover elimina (D1/D3).
 *
 * Decisão deste lote (sem inventar dado):
 * - o view-model **mantém o UUID como identidade** (`colaboradorId`,
 *   `autorCollaboratorId`) — todas as operações da Edge são por UUID;
 * - os RÓTULOS (matrícula/nome) chegam por PARÂMETRO, de outra superfície
 *   soberana (colaboradores, F5-07) que a página já consulta;
 * - rótulo do colaborador-ALVO ausente ⇒ o item NÃO é apresentado (`null`);
 * - o AUTOR é anulável por schema (`author_collaborator_id`): quando o autor é
 *   `null` na LINHA, o rótulo é `null` — o mapeador **nunca** usa `0`, `""` ou
 *   "desconhecido" como se fosse identidade;
 * - `ano`/`ciclo` legados NÃO são derivados (a projeção traz `cycleId` UUID):
 *   inventar a numeração reintroduziria autoridade local;
 * - a TIMELINE tem tipo NOVO e independente (`EventoTimelineUi`) e chega da
 *   operação soberana de histórico (`observacao.historico`): o rótulo do ATOR é
 *   resolvido por PARÂMETRO (colaborador do ator **ou** nome de perfil) e o
 *   texto anterior vem da imagem `before_value` do evento — nada é derivado de
 *   UUID, de matrícula ou de "ação" textual.
 *
 * `ObservacaoDeUi` é um tipo NOVO e independente do legado `Observacao` (que
 * permanece intocado): o legado exige matrícula numérica obrigatória, e forçá-la
 * aqui só seria possível inventando identidade. O cutover das páginas (L3) adota
 * este view-model.
 */

import type {
  EventoHistoricoSoberano,
  ObservacaoSoberana,
} from "../../application/ports/ObservationRepository";
import type { TipoEventoObservacao } from "../../infrastructure/supabase/observacoes/contrato";
import type { TipoObservacao } from "../../types/Observacao";

/** Rótulo de apresentação de um colaborador (dado de OUTRA superfície soberana). */
export interface RotuloColaborador {
  /**
   * Matrícula é APRESENTAÇÃO e pode não existir na superfície que fornece os
   * rótulos (ex.: mapa de nomes da página do colaborador). Ausente ⇒ permanece
   * `null` no view-model — **nunca** `0`, `""` ou sentinela.
   */
  readonly matricula?: number;
  readonly nome: string;
}

/** Fonte de rótulos por UUID — em geral a superfície de colaboradores da página. */
export interface FonteDeRotulosDeColaborador {
  /** Rótulo do colaborador-ALVO; `null` = desconhecido (item não é apresentado). */
  doColaborador(collaboratorId: string): RotuloColaborador | null;
  /** Rótulo do AUTOR (`null` quando a própria linha não tem autor). */
  doAutor(collaboratorId: string): RotuloColaborador | null;
}

/**
 * View-model soberano de UMA observação. `id` e os UUIDs de identidade são os
 * únicos identificadores; matrícula/nome são apresentação e podem faltar
 * (`null`) quando o FATO é ausente — nunca são substituídos por sentinela.
 */
export interface ObservacaoDeUi {
  readonly id: string;
  readonly colaboradorId: string;
  readonly colaboradorMatricula: number | null;
  readonly colaboradorNome: string;
  readonly autorCollaboratorId: string | null;
  readonly autorMatricula: number | null;
  readonly autorNome: string | null;
  readonly tipo: TipoObservacao;
  readonly texto: string;
  readonly comunicado: boolean;
  /** Data soberana da comunicação; `null` = nunca comunicada. */
  readonly comunicadoEm: string | null;
  readonly excluida: boolean;
  readonly motivoExclusao: string | null;
  readonly version: number;
  readonly dataCriacao: string;
  readonly dataUltimaAtualizacao: string;
  /**
   * Itens da timeline já mapeados (tipo NOVO e independente do legado). Vazio =
   * trilha não lida/não disponível — nunca preenchido por derivação local.
   */
  readonly timeline: readonly EventoTimelineUi[];
}

// ---------------------------------------------------------------------------
// Timeline soberana (tipo NOVO, independente de `HistoricoObservacao`)
// ---------------------------------------------------------------------------

/**
 * Item de timeline soberano. A identidade é `eventId`/`actorUserProfileId`
 * (UUID); `beforeValue`/`afterValue` são as imagens JSON do evento e
 * `textoAnterior` é o FATO (`before_value.texto`) do evento de edição.
 */
export interface EventoTimelineUi {
  readonly eventId: string;
  readonly evento: TipoEventoObservacao;
  /** Instante EFETIVO do fato (`effective_date`, gravado pelo servidor). */
  readonly dataEfetiva: string;
  /** Motivo do fato; `null` = evento sem motivo registrado. */
  readonly motivo: string | null;
  readonly beforeValue: Readonly<Record<string, unknown>> | null;
  readonly afterValue: Readonly<Record<string, unknown>> | null;
  readonly payloadHash: string;
  readonly actorUserProfileId: string;
  readonly actorCollaboratorId: string | null;
  /**
   * Rótulo do ator por PARÂMETRO; `null` = rótulo indisponível (nunca inventado,
   * nunca "desconhecido", nunca matrícula `0`).
   */
  readonly actorMatricula: number | null;
  readonly actorNome: string | null;
  readonly operationId: string;
  readonly criadoEm: string;
  /** Texto anterior ao fato (`before_value.texto`); `null` = fato ausente. */
  readonly textoAnterior: string | null;
}

/**
 * Fonte de rótulos de ATOR por UUID de **perfil** (`actor_user_profile_id`). É o
 * único caminho para apresentar o ator: um ator pode não ter vínculo de
 * colaborador (coluna anulável), e nesse caso a fonte devolve `null`.
 */
export interface FonteDeRotulosDeAtor {
  doAtor(actorUserProfileId: string): RotuloColaborador | null;
}

/**
 * Rótulos de apresentação do evento. `rotuloDoAtor` é o caminho padrão (perfil →
 * rótulo). `getEventoHistorico` é um gancho OPCIONAL para uma superfície que já
 * tenha enriquecido o evento (ex.: mapeador de outro consumidor): quando
 * presente, ele é a ÚNICA fonte do item — o módulo não inventa rótulo nem
 * identidade para preencher a lacuna.
 */
export interface RotulosTimelineObservacao {
  readonly rotuloDoAtor?: FonteDeRotulosDeAtor;
  readonly getEventoHistorico?: (evento: EventoHistoricoSoberano) => EventoTimelineUi | null;
}

/** Imagem JSON (`before_value`/`after_value`) → texto anterior do evento. */
export function textoAnteriorDoEvento(evento: EventoHistoricoSoberano): string | null {
  const texto = evento.beforeValue?.["texto"];
  return typeof texto === "string" ? texto : null;
}

/** Rótulo do ator por PARÂMETRO; ausente ⇒ `null` (nunca sentinela). */
function rotuloDeAtor(
  evento: EventoHistoricoSoberano,
  rotulos: RotulosTimelineObservacao
): RotuloColaborador | null {
  return rotulos.rotuloDoAtor?.doAtor(evento.actorUserProfileId) ?? null;
}

/**
 * Projeta UM evento da trilha para a timeline. `getEventoHistorico`, quando
 * informado, tem precedência e pode devolver `null` (item NÃO apresentado).
 */
export function eventoTimelineDeUi(
  evento: EventoHistoricoSoberano,
  rotulos: RotulosTimelineObservacao = {}
): EventoTimelineUi | null {
  if (rotulos.getEventoHistorico) return rotulos.getEventoHistorico(evento);

  const autor = rotuloDeAtor(evento, rotulos);

  return {
    eventId: evento.id,
    evento: evento.evento,
    dataEfetiva: evento.dataEfetiva,
    motivo: evento.motivo,
    beforeValue: evento.beforeValue,
    afterValue: evento.afterValue,
    payloadHash: evento.payloadHash,
    actorUserProfileId: evento.actorUserProfileId,
    actorCollaboratorId: evento.actorCollaboratorId,
    actorMatricula: autor?.matricula ?? null,
    actorNome: autor?.nome ?? null,
    operationId: evento.operationId,
    criadoEm: evento.criadoEm,
    textoAnterior: textoAnteriorDoEvento(evento),
  };
}

/** Projeta a trilha inteira, DESCARTANDO o que não for apresentável. */
export function timelineDeUi(
  eventos: readonly EventoHistoricoSoberano[],
  rotulos: RotulosTimelineObservacao = {}
): EventoTimelineUi[] {
  const itens: EventoTimelineUi[] = [];
  for (const evento of eventos) {
    const item = eventoTimelineDeUi(evento, rotulos);
    if (item) itens.push(item);
  }
  return itens;
}

/**
 * Projeta a observação soberana para a UI. `null` = não apresentável (rótulo do
 * colaborador-alvo ausente) — fail-closed: nunca inventa matrícula/nome/autor.
 *
 * `timeline` entra por PARÂMETRO já mapeada (`timelineDeUi`) ou é derivada dos
 * próprios eventos soberanos via `rotulosTimeline` — nunca de histórico local.
 */
export function observacaoDeUi(
  soberana: ObservacaoSoberana,
  rotulos: FonteDeRotulosDeColaborador,
  timeline: readonly EventoTimelineUi[] = []
): ObservacaoDeUi | null {
  const alvo = rotulos.doColaborador(soberana.collaboratorId);
  if (!alvo) return null;

  const autorId = soberana.autorCollaboratorId;
  const autor = autorId === null ? null : rotulos.doAutor(autorId);

  return {
    id: soberana.id,
    colaboradorId: soberana.collaboratorId,
    colaboradorMatricula: alvo.matricula ?? null,
    colaboradorNome: alvo.nome,
    autorCollaboratorId: autorId,
    autorMatricula: autor?.matricula ?? null,
    autorNome: autor?.nome ?? null,
    tipo: soberana.tipo,
    texto: soberana.texto,
    comunicado: soberana.comunicado,
    comunicadoEm: soberana.comunicadoEm,
    excluida: soberana.excluida,
    motivoExclusao: soberana.motivoExclusao,
    version: soberana.version,
    dataCriacao: soberana.criadoEm,
    dataUltimaAtualizacao: soberana.atualizadoEm,
    timeline: [...timeline],
  };
}
