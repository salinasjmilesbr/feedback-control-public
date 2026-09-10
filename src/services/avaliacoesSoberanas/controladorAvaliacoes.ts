/**
 * F5-06 (Issue #103) — CONTROLADOR do caminho novo de avaliações.
 *
 * Concentra a lógica de estado (carregar, criar, gravar, concluir, reabrir,
 * cancelar, transparência) de forma INDEPENDENTE de React, o que o torna
 * testável sem DOM. O hook (`useAvaliacoesSoberanas`) é apenas a cola reativa
 * sobre este controlador.
 *
 * Invariantes:
 * - erro do servidor vira `erro` de UI (nunca lança para a página);
 * - depois de qualquer mutação bem-sucedida o acervo é RECARREGADO do servidor
 *   (a autoridade é o banco, nunca o estado local);
 * - nenhuma regra de autorização ou de cálculo oficial vive aqui;
 * - nada é escrito em `localStorage` (sem dual-write, D12/§11).
 */

import type { AvaliacaoSoberana } from "../../infrastructure/supabase/avaliacoes/repositorioAvaliacoes.ts";
import {
  mensagemErroAvaliacoes,
  type DadosAcervoAvaliacoes,
  type ServiceAvaliacoes,
} from "./serviceAvaliacoes.ts";
import { statusEditavel } from "./estadoAvaliacao.ts";

export { statusEditavel };

export interface EstadoAvaliacoesSoberanas<Registro = unknown> {
  readonly carregando: boolean;
  readonly erro: string | null;
  readonly acervo: DadosAcervoAvaliacoes<Registro> | null;
  readonly avaliacaoSelecionada: AvaliacaoSoberana | null;
}

export interface EntradaControladorAvaliacoes<Registro = unknown> {
  readonly service: ServiceAvaliacoes<Registro>;
  readonly organizationId: string;
  readonly cycleId: string;
  /** Ids técnicos (UUID) das avaliações já conhecidas do ciclo. */
  readonly evaluationIds: readonly string[];
  /** Regra de domínio declarada pela fronteira (nunca autorização de UI). */
  readonly ehEditavel?: (avaliacao: AvaliacaoSoberana) => boolean;
  readonly aoMudar?: (estado: EstadoAvaliacoesSoberanas<Registro>) => void;
}

export interface ControladorAvaliacoes<Registro = unknown> {
  estado(): EstadoAvaliacoesSoberanas<Registro>;
  carregar(entrada?: { readonly evaluationIds?: readonly string[] }): Promise<void>;
  selecionar(evaluationId: string): Promise<void>;
  criar(entrada: {
    readonly cycleId: string;
    readonly evaluatedCollaboratorId: string;
  }): Promise<string | null>;
  /**
   * Grava notas da PRÓPRIA ocorrência. CORREÇÃO DE AUDITORIA (IDOR): NÃO existe
   * `participantId` — a ocorrência é resolvida na fronteira confiável a partir
   * do ator autenticado.
   */
  gravarNotas(entrada: {
    readonly evaluationId: string;
    readonly notas: readonly { readonly subcriterion_id: string; readonly nota: number }[];
  }): Promise<boolean>;
  /** Grava comentário da PRÓPRIA ocorrência (sem `participantId`). */
  gravarComentario(entrada: {
    readonly evaluationId: string;
    readonly escopo: "CRITERIO" | "FINAL";
    readonly criterionId?: string | null;
    readonly texto: string;
  }): Promise<boolean>;
  concluir(evaluationId: string): Promise<boolean>;
  reabrir(entrada: { readonly evaluationId: string; readonly motivo: string }): Promise<boolean>;
  cancelar(entrada: { readonly evaluationId: string; readonly motivo: string }): Promise<boolean>;
}

export function criarControladorAvaliacoes<Registro = unknown>(
  deps: EntradaControladorAvaliacoes<Registro>
): ControladorAvaliacoes<Registro> {
  const ehEditavel = deps.ehEditavel ?? statusEditavel;
  let evaluationIds: readonly string[] = deps.evaluationIds;
  let estado: EstadoAvaliacoesSoberanas<Registro> = {
    carregando: false,
    erro: null,
    acervo: null,
    avaliacaoSelecionada: null,
  };

  function publicar(parcial: Partial<EstadoAvaliacoesSoberanas<Registro>>): void {
    estado = { ...estado, ...parcial };
    deps.aoMudar?.(estado);
  }

  async function recarregar(): Promise<void> {
    const resultado = await deps.service.listarAcervo({
      organizationId: deps.organizationId,
      cycleId: deps.cycleId,
      evaluationIds,
      ehEditavel,
    });
    if (!resultado.ok) {
      publicar({ carregando: false, erro: mensagemErroAvaliacoes(resultado.error) });
      return;
    }
    publicar({ carregando: false, erro: null, acervo: resultado.data });
  }

  async function mutar(
    acao: () => Promise<{ readonly ok: boolean; readonly mensagem?: string }>
  ): Promise<boolean> {
    publicar({ carregando: true, erro: null });
    const resultado = await acao();
    if (!resultado.ok) {
      publicar({ carregando: false, erro: resultado.mensagem ?? "Operação recusada." });
      return false;
    }
    // A autoridade é o servidor: recarrega em vez de aplicar estado local.
    await recarregar();
    return true;
  }

  return {
    estado: () => estado,

    async carregar(entrada) {
      if (entrada?.evaluationIds) evaluationIds = entrada.evaluationIds;
      publicar({ carregando: true, erro: null });
      await recarregar();
    },

    async selecionar(evaluationId) {
      publicar({ carregando: true, erro: null });
      const resultado = await deps.service.ler({
        organizationId: deps.organizationId,
        evaluationId,
      });
      if (!resultado.ok) {
        publicar({ carregando: false, erro: mensagemErroAvaliacoes(resultado.error) });
        return;
      }
      publicar({ carregando: false, erro: null, avaliacaoSelecionada: resultado.data });
    },

    async criar({ cycleId, evaluatedCollaboratorId }) {
      publicar({ carregando: true, erro: null });
      const resultado = await deps.service.criar({
        organizationId: deps.organizationId,
        cycleId,
        evaluatedCollaboratorId,
      });
      if (!resultado.ok) {
        publicar({ carregando: false, erro: mensagemErroAvaliacoes(resultado.error) });
        return null;
      }
      const novoId = resultado.data.evaluationId;
      if (!evaluationIds.includes(novoId)) {
        evaluationIds = [...evaluationIds, novoId];
      }
      await recarregar();
      return novoId;
    },

    gravarNotas(entrada) {
      return mutar(async () => {
        const resultado = await deps.service.gravarNotas({
          organizationId: deps.organizationId,
          ...entrada,
        });
        return resultado.ok
          ? { ok: true }
          : { ok: false, mensagem: mensagemErroAvaliacoes(resultado.error) };
      });
    },

    gravarComentario(entrada) {
      return mutar(async () => {
        const resultado = await deps.service.gravarComentario({
          organizationId: deps.organizationId,
          ...entrada,
        });
        return resultado.ok
          ? { ok: true }
          : { ok: false, mensagem: mensagemErroAvaliacoes(resultado.error) };
      });
    },

    concluir(evaluationId) {
      return mutar(async () => {
        const resultado = await deps.service.concluir({
          organizationId: deps.organizationId,
          evaluationId,
        });
        return resultado.ok
          ? { ok: true }
          : { ok: false, mensagem: mensagemErroAvaliacoes(resultado.error) };
      });
    },

    reabrir({ evaluationId, motivo }) {
      return mutar(async () => {
        const resultado = await deps.service.reabrir({
          organizationId: deps.organizationId,
          evaluationId,
          motivo,
        });
        return resultado.ok
          ? { ok: true }
          : { ok: false, mensagem: mensagemErroAvaliacoes(resultado.error) };
      });
    },

    cancelar({ evaluationId, motivo }) {
      return mutar(async () => {
        const resultado = await deps.service.cancelar({
          organizationId: deps.organizationId,
          evaluationId,
          motivo,
        });
        return resultado.ok
          ? { ok: true }
          : { ok: false, mensagem: mensagemErroAvaliacoes(resultado.error) };
      });
    },
  };
}
