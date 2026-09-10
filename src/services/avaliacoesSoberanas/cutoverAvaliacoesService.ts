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
import { mensagemErroAvaliacoes } from "./serviceAvaliacoes.ts";
import { registrarAvaliacaoCortada, type ArmazenamentoCutover } from "../../infrastructure/supabase/avaliacoes/cutover.ts";
import { ehIdTecnicoPostgres } from "../../infrastructure/supabase/avaliacoes/cutover.ts";

export interface ResultadoCutover<T> {
  readonly ok: boolean;
  readonly data?: T;
  readonly erro?: string;
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
  /** Notas da própria ocorrência (participant_id vem do painel, server-side). */
  gravarNotasDoPainel(entrada: {
    readonly organizationId: string;
    readonly evaluationId: string;
    readonly painel: PainelParticipante;
    readonly notas: readonly { readonly subcriterionId: string; readonly nota: number }[];
  }): Promise<ResultadoCutover<number | null>>;
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
  return { ok: false, erro: mensagemErroAvaliacoes(erro) };
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

      // 2) criação no PostgreSQL: a matrícula é novamente resolvida no Edge e
      //    prevalece sobre qualquer identidade vinda do cliente.
      const criada = await deps.repositorio.criar({
        organizationId: entrada.organizationId,
        cycleId: ciclo.data,
        evaluatedCollaboratorId: ciclo.data,
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
      const paraGravar: EntradaGravarNotas = {
        organizationId: entrada.organizationId,
        evaluationId: entrada.evaluationId,
        participantId: entrada.painel.participanteOcorrenciaId,
        notas: entrada.notas.map((nota) => ({
          subcriterion_id: nota.subcriterionId,
          nota: nota.nota,
        })),
      };
      return propagar(await deps.repositorio.gravarNotas(paraGravar), (data) => data);
    },

    async gravarComentarioDoPainel(entrada) {
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
