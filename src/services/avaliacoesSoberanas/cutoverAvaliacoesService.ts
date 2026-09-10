/**
 * F5-06 (Issue #103) — CUTOVER das telas: orquestração soberana de criação,
 * edição, conclusão, cancelamento e reabertura.
 *
 * Esta camada é o ÚNICO caminho pelo qual uma avaliação NOVA é criada, editada
 * ou encerrada no produto. Ela:
 *
 * - resolve ano+ciclo → UUID do ciclo na fronteira confiável (decisão 2);
 * - resolve matrícula → UUID do colaborador na fronteira confiável (F3-01);
 * - cria/edita/conclui/cancela/reabre via repository → Edge → Policy Engine →
 *   RPC (decisão 1);
 * - NUNCA escreve em `localStorage`, NUNCA faz dual-write e NUNCA cai para o
 *   caminho legado quando o backend falha (fail-closed com erro público);
 * - NÃO calcula nota oficial: `nota_media` e agregados vêm materializados do
 *   banco; a tela apenas apresenta.
 */

import type {
  AvaliacaoSoberana,
  EntradaGravarComentario,
  EntradaGravarNotas,
  ErroRepositorioAvaliacoes,
  PainelParticipante,
  RepositorioAvaliacoes,
  ResultadoRepositorio,
} from "../../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";
import type { CodigoPublico } from "../../infrastructure/supabase/avaliacoes/contrato.ts";
import { mensagemErroAvaliacoes } from "./serviceAvaliacoes.ts";
import { registrarAvaliacaoCortada, type ArmazenamentoCutover } from "../../infrastructure/supabase/avaliacoes/cutover.ts";
import { ehIdTecnicoPostgres } from "../../infrastructure/supabase/avaliacoes/cutover.ts";

export interface ResultadoCutover<T> {
  readonly ok: boolean;
  readonly data?: T;
  readonly erro?: string;
  /**
   * Código PÚBLICO do erro (F0-05), quando houver. Permite ao chamador
   * distinguir RESPOSTA do servidor ("não existe") de INDETERMINAÇÃO (falha de
   * autorização/rede) sem inspecionar texto — a mensagem é para o usuário.
   */
  readonly codigo?: CodigoPublico;
}

export interface AvaliacaoNovaCriada {
  readonly evaluationId: string;
  readonly cycleId: string;
  /** Registro do cutover: avaliação existe EXCLUSIVAMENTE no PostgreSQL. */
  readonly cutoverRegistrado: boolean;
}

export interface EntradaCriarAvaliacaoNova {
  readonly organizationId: string;
  /** Intenção da tela: ano e número do ciclo. */
  readonly ano: number;
  readonly ciclo: number;
  /** Intenção da tela: matrícula do colaborador avaliado. */
  readonly matriculaAvaliado: number;
}

/**
 * Conversão ESTRUTURAL entre o vocabulário da tela (nome do critério/
 * subcritério) e o UUID da configuração CONGELADA da avaliação (D6). A tela do
 * produto trabalha com nomes; o banco só aceita UUID. Nenhum id é inventado no
 * cliente: o painel entrega o catálogo congelado e um nome sem correspondência
 * recusa o lote inteiro (fail-closed).
 */
export interface MapaCatalogoPainel {
  readonly subcriterioIdPorNome: ReadonlyMap<string, string>;
  readonly criterioIdPorCode: ReadonlyMap<string, string>;
}

export function montarMapaCatalogo(painel: PainelParticipante): MapaCatalogoPainel {
  const subcriterioIdPorNome = new Map<string, string>();
  for (const subcriterio of painel.subcriterios) {
    subcriterioIdPorNome.set(subcriterio.name, subcriterio.subcriterionId);
  }
  const criterioIdPorCode = new Map<string, string>();
  for (const criterio of painel.criterios) {
    criterioIdPorCode.set(criterio.code, criterio.criterionId);
  }
  return { subcriterioIdPorNome, criterioIdPorCode };
}

/** Nota informada pela tela por NOME do subcritério (nunca por id). */
export interface NotaDoPainelPorNome {
  readonly subcriterio: string;
  readonly nota: number;
}

/** Observação de critério informada pela tela (escopo CRITERIO). */
export interface ObservacaoDoPainel {
  readonly criterioCode: string;
  readonly texto: string;
}

export interface DepsCutoverAvaliacoes {
  readonly repositorio: RepositorioAvaliacoes;
  readonly armazenamento?: ArmazenamentoCutover | null;
}

export interface CutoverAvaliacoes {
  /** Cria avaliação NOVA: resolve ciclo + colaborador e cria no PostgreSQL. */
  criarNova(
    entrada: EntradaCriarAvaliacaoNova
  ): Promise<ResultadoCutover<AvaliacaoNovaCriada>>;
  /** Painel de EDIÇÃO: somente a própria ocorrência do ator autenticado. */
  carregarPainel(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
  }): Promise<ResultadoCutover<PainelParticipante>>;
  /**
   * Notas da própria ocorrência (participant_id vem do painel, server-side).
   * A tela informa o NOME do subcritério; a conversão para o UUID da
   * configuração congelada é estrutural e recusa nome desconhecido.
   */
  gravarNotasDoPainel(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly painel: PainelParticipante;
    readonly notas: readonly NotaDoPainelPorNome[];
  }): Promise<ResultadoCutover<number | null>>;
  /** Observações de critério da própria ocorrência (escopo CRITERIO). */
  gravarObservacoesDoPainel(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly painel: PainelParticipante;
    readonly observacoes: readonly ObservacaoDoPainel[];
  }): Promise<ResultadoCutover<number>>;
  /** Comentário final da própria ocorrência (escopo FINAL). */
  gravarComentarioFinalDoPainel(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly painel: PainelParticipante;
    readonly texto: string;
  }): Promise<ResultadoCutover<null>>;
  /** Comentários da própria ocorrência (critério ou final). */
  gravarComentarioDoPainel(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly painel: PainelParticipante;
    readonly escopo: "CRITERIO" | "FINAL";
    readonly criterionId?: string | null;
    readonly texto: string;
  }): Promise<ResultadoCutover<null>>;
  /** Conclusão: o cálculo e a completude são oficiais no SQL. */
  concluir(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
  }): Promise<ResultadoCutover<null>>;
  cancelar(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly motivo: string;
  }): Promise<ResultadoCutover<null>>;
  reabrir(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly motivo: string;
  }): Promise<ResultadoCutover<null>>;
  /** Estado real do banco (nunca projeção legada). */
  lerStatus(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
  }): Promise<ResultadoCutover<AvaliacaoSoberana | null>>;
}

function falha<T>(erro: ErroRepositorioAvaliacoes): ResultadoCutover<T> {
  return { ok: false, erro: mensagemErroAvaliacoes(erro), codigo: erro.code };
}

function propagar<T, U>(
  resultado: ResultadoRepositorio<T>,
  mapear: (data: T) => U
): ResultadoCutover<U> {
  if (!resultado.ok) return falha(resultado.error);
  return { ok: true, data: mapear(resultado.data) };
}

export function criarCutoverAvaliacoes(
  deps: DepsCutoverAvaliacoes
): CutoverAvaliacoes {
  const armazenamento = deps.armazenamento ?? null;

  /**
   * Fonte única da gravação de comentário da PRÓPRIA ocorrência, usada tanto
   * pelo comentário de critério quanto pelo comentário final. A ocorrência vem
   * SEMPRE do painel (resolvida server-side): o cliente nunca escolhe
   * `participant_id`.
   */
  async function gravarComentario(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly painel: PainelParticipante;
    readonly escopo: "CRITERIO" | "FINAL";
    readonly criterionId?: string | null;
    readonly texto: string;
  }): Promise<ResultadoCutover<null>> {
    if (!ehIdTecnicoPostgres(entrada.painel.participanteOcorrenciaId)) {
      return { ok: false, erro: "Ocorrência do participante não resolvida." };
    }
    const paraGravar: EntradaGravarComentario = {
      organizationId: entrada.organizationId,
      evaluationId: entrada.evaluationId,
      participantId: entrada.painel.participanteOcorrenciaId,
      escopo: entrada.escopo,
      criterionId: entrada.criterionId ?? null,
      texto: entrada.texto,
    };
    return propagar(await deps.repositorio.gravarComentario(paraGravar), () => null);
  }

  return {
    async criarNova(entrada) {
      // 1) ano+ciclo (INTENÇÃO) → UUID soberano do ciclo, dentro do tenant. O
      //    Edge também resolve a matrícula para o ALVO autorizável (F3-01).
      const ciclo = await deps.repositorio.resolverCiclo({
        organizationId: entrada.organizationId,
        ano: entrada.ano,
        numero: entrada.ciclo,
        matriculaAvaliado: entrada.matriculaAvaliado,
      });
      if (!ciclo.ok) return falha(ciclo.error);
      if (!ehIdTecnicoPostgres(ciclo.data)) {
        return { ok: false, erro: "Ciclo não resolvido para a avaliação." };
      }

      // 2) criação no PostgreSQL. O ALVO autorizável é o colaborador resolvido
      //    da matrícula (ponte F3-01) na fronteira confiável: o cliente nunca
      //    fornece o alvo. Usar o UUID do CICLO como se fosse o do colaborador
      //    apresentaria um alvo de outro TIPO à autorização, então a identidade
      //    do avaliado é derivada server-side de `matriculaAvaliado` — sem essa
      //    ponte a criação é recusada (fail-closed), nunca inventada.
      const criada = await deps.repositorio.criar({
        organizationId: entrada.organizationId,
        cycleId: ciclo.data,
        matriculaAvaliado: entrada.matriculaAvaliado,
      });
      if (!criada.ok) return falha(criada.error);

      const evaluationId = criada.data;
      const cutoverRegistrado = ehIdTecnicoPostgres(evaluationId);
      if (cutoverRegistrado) registrarAvaliacaoCortada(evaluationId, armazenamento);

      return {
        ok: true,
        data: { evaluationId, cycleId: ciclo.data, cutoverRegistrado },
      };
    },

    async carregarPainel(entrada) {
      const resultado = await deps.repositorio.painelParticipante(entrada);
      if (!resultado.ok) return falha(resultado.error);
      return { ok: true, data: resultado.data };
    },

    async gravarNotasDoPainel(entrada) {
      // A ocorrência é SEMPRE a do painel (resolvida server-side); o cliente
      // nunca escolhe participant_id.
      if (!ehIdTecnicoPostgres(entrada.painel.participanteOcorrenciaId)) {
        return { ok: false, erro: "Ocorrência do participante não resolvida." };
      }
      const mapa = montarMapaCatalogo(entrada.painel);

      // Resolução estrutural nome → UUID da configuração congelada. Uma nota
      // para nome desconhecido é recusada: nada é gravado pela metade.
      const resolvidas: { subcriterion_id: string; nota: number }[] = [];
      for (const nota of entrada.notas) {
        const subcriterionId = mapa.subcriterioIdPorNome.get(nota.subcriterio);
        if (!ehIdTecnicoPostgres(subcriterionId)) {
          return {
            ok: false,
            erro: `Subcritério "${nota.subcriterio}" não pertence à configuração desta avaliação.`,
          };
        }
        resolvidas.push({ subcriterion_id: subcriterionId, nota: nota.nota });
      }

      if (resolvidas.length === 0) return { ok: true, data: null };

      const paraGravar: EntradaGravarNotas = {
        organizationId: entrada.organizationId,
        evaluationId: entrada.evaluationId,
        participantId: entrada.painel.participanteOcorrenciaId,
        notas: resolvidas,
      };
      return propagar(await deps.repositorio.gravarNotas(paraGravar), (data) => data);
    },

    async gravarObservacoesDoPainel(entrada) {
      if (!ehIdTecnicoPostgres(entrada.painel.participanteOcorrenciaId)) {
        return { ok: false, erro: "Ocorrência do participante não resolvida." };
      }
      const mapa = montarMapaCatalogo(entrada.painel);
      let gravadas = 0;

      for (const observacao of entrada.observacoes) {
        if (!observacao.texto.trim()) continue;
        const criterionId = mapa.criterioIdPorCode.get(observacao.criterioCode);
        if (!ehIdTecnicoPostgres(criterionId)) {
          return {
            ok: false,
            erro: `Critério "${observacao.criterioCode}" não pertence à configuração desta avaliação.`,
          };
        }
        const resultado = await deps.repositorio.gravarComentario({
          organizationId: entrada.organizationId,
          evaluationId: entrada.evaluationId,
          participantId: entrada.painel.participanteOcorrenciaId,
          escopo: "CRITERIO",
          criterionId,
          texto: observacao.texto,
        });
        if (!resultado.ok) return falha(resultado.error);
        gravadas += 1;
      }

      return { ok: true, data: gravadas };
    },

    async gravarComentarioFinalDoPainel(entrada) {
      if (!entrada.texto.trim()) return { ok: true, data: null };
      return gravarComentario({
        organizationId: entrada.organizationId,
        evaluationId: entrada.evaluationId,
        painel: entrada.painel,
        escopo: "FINAL",
        texto: entrada.texto,
      });
    },

    gravarComentarioDoPainel(entrada) {
      return gravarComentario(entrada);
    },

    async concluir(entrada) {
      return propagar(await deps.repositorio.concluir(entrada), () => null);
    },

    async cancelar(entrada) {
      return propagar(await deps.repositorio.cancelar(entrada), () => null);
    },

    async reabrir(entrada) {
      return propagar(await deps.repositorio.reabrir(entrada), () => null);
    },

    async lerStatus(entrada) {
      return propagar(await deps.repositorio.ler(entrada), (data) => data);
    },
  };
}
