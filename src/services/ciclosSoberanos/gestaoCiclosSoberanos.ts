/**
 * F5-09 P8 (Issue #204) — CUTOVER da GESTÃO DE CICLOS para o caminho SOBERANO.
 *
 * Fronteira única do fluxo ativo de gestão (lista + mutações):
 *
 *   LEITURA  → `acessoCiclosSoberanos` (contrato P5/P6) → PostgREST + RLS → PostgreSQL
 *   MUTAÇÃO  → `edgeCiclos` (adapter P7) → Edge `ciclos` → Policy Engine → RPC → PostgreSQL
 *
 * O que este módulo NÃO faz (e é proibido no fluxo ativo):
 * - gerar UUID de CICLO no cliente (a identidade canônica é `evaluation_cycles.id`,
 *   atribuída pelo banco);
 * - decidir/persistir lifecycle (status vem do estado soberano);
 * - gravar qualquer coisa em `localStorage` (sem dual-write, sem espelho);
 * - cair para dado local quando o backend falha (fail-closed: erro público).
 *
 * `(ano, numero)` aparecem apenas como RÓTULOS de apresentação (`CicloAvaliacao`
 * legado é usado só como modelo de VIEW) — nunca como identidade, chave de leitura
 * ou autorização.
 *
 * `operationId` É gerado no cliente de propósito: é a CHAVE DE IDEMPOTÊNCIA do
 * contrato da Edge (§13.1) — não é identidade de ciclo.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import type { CicloSoberano, ResultadoCiclos } from "../../application/ports/CycleRepository";
import type { CicloAvaliacao } from "../../types/CicloAvaliacao";
import {
  criarEdgeCiclos,
  type EdgeCiclos,
  type ResultadoEdgeCiclos,
} from "../../infrastructure/supabase/ciclos/edgeCiclos";
import {
  criarControladorCiclosSoberanos,
  obterRepositorioCiclosSoberanos,
  type ControladorCiclosSoberanos,
  type DependenciasAcessoCiclos,
  type EstadoCiclosSoberanos,
} from "../acessoCiclosSoberanos";

/** Erro público do fluxo de gestão (código estável + mensagem sem detalhe do banco). */
export interface FalhaGestaoCiclos {
  readonly code: string;
  readonly message: string;
}

export type ResultadoGestao<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: FalhaGestaoCiclos };

/**
 * Projeção de APRESENTAÇÃO: `CicloSoberano` → modelo de view legado.
 *
 * Puramente visual (o JSX existente consome esses campos). Não cria histórico,
 * não inventa contadores e NÃO gera identidade: `id` é o UUID soberano.
 * Os campos de trilha (`cancelamento`, `reaberturas`, `correcoesPeriodo`,
 * `encerramentos`) NÃO existem no contrato soberano de leitura — a trilha é
 * `cycle_events`, que permanece deny-by-default por decisão de contrato — e por
 * isso ficam ausentes (a UI trata como histórico indisponível nesta fase).
 */
export function projetarCicloParaUi(ciclo: CicloSoberano): CicloAvaliacao {
  return {
    id: ciclo.id,
    ano: ciclo.ano,
    ciclo: ciclo.numero,
    status: ciclo.status,
    dataInicio: ciclo.dataInicio ?? undefined,
    dataFim: ciclo.dataFim ?? undefined,
    dataAtivacao: ciclo.dataAtivacao ?? undefined,
    dataEncerramento: ciclo.dataEncerramento ?? undefined,
    encerradoComPendencias: ciclo.encerradoComPendencias,
    quantidadePendencias: ciclo.quantidadePendencias,
    dataCriacao: ciclo.criadoEm,
    dataUltimaAtualizacao: ciclo.atualizadoEm,
  };
}

/** Versão otimista da linha soberana (base de `expectedVersion`). */
export function versaoDoSoberano(ciclo: CicloSoberano): number {
  return ciclo.version;
}

export interface DependenciasGestaoCiclos extends DependenciasAcessoCiclos {
  readonly edge?: EdgeCiclos;
}

/**
 * Chave de IDEMPOTÊNCIA do contrato da Edge (não é identidade de ciclo).
 * Centralizada para deixar explícito que NENHUM id de ciclo nasce no cliente.
 */
export function novoOperationId(): string {
  return crypto.randomUUID();
}

function falha(error: { readonly code: string; readonly message: string }): {
  readonly ok: false;
  readonly error: FalhaGestaoCiclos;
} {
  return { ok: false, error: { code: error.code, message: error.message } };
}

function projetarResultadoEdge(
  resultado: ResultadoEdgeCiclos<unknown>
): ResultadoGestao<unknown> {
  return resultado.ok ? { ok: true, data: resultado.data } : falha(resultado.error);
}

/**
 * Fábrica da fronteira de gestão. As dependências são injetáveis (testes);
 * em produção usam o caminho soberano já entregue (P5/P6/P7) — sem fallback.
 */
export function criarGestaoCiclosSoberanos(deps: DependenciasGestaoCiclos = {}) {
  function controlador(): ControladorCiclosSoberanos {
    return criarControladorCiclosSoberanos(deps);
  }

  function edge(): EdgeCiclos | null {
    if (deps.edge) return deps.edge;
    const repositorio = obterRepositorioCiclosSoberanos(deps);
    if (!repositorio) return null;
    // O mesmo cliente soberano do repositório (fail-closed quando ausente).
    const cliente = (deps.cliente ?? undefined) as SupabaseClient | undefined;
    return cliente ? criarEdgeCiclos(cliente) : null;
  }

  return {
    /** Cria um controlador novo (cache de UX com proteção de resposta obsoleta). */
    controlador,

    /** Ciclos do tenant (ordem soberana), projetados para a UI. */
    async listar(
      organizationId: string,
      opcoes: { readonly incluirCancelados?: boolean } = {}
    ): Promise<ResultadoGestao<readonly CicloAvaliacao[]>> {
      const resultado = await controlador().carregar(organizationId);
      if (!resultado.ok) return falha(resultado.error);
      const ciclos = opcoes.incluirCancelados
        ? resultado.data
        : resultado.data.filter((ciclo) => ciclo.status !== "CANCELADO");
      return { ok: true, data: ciclos.map(projetarCicloParaUi) };
    },

    /** Estado publicado pelo controlador (para telas que observam a cache de UX). */
    estado(): EstadoCiclosSoberanos {
      return controlador().estado();
    },

    /**
     * MUTAÇÕES: apenas INTENÇÃO (alvo UUID + versão esperada + operação). Nenhum
     * campo de autoridade (actor/role/cargo/função/status) atravessa daqui.
     */
    async criar(entrada: {
      readonly organizationId: string;
      readonly ano: number;
      readonly numero: 1 | 2 | 3;
      readonly dataInicio: string;
      readonly dataFim: string;
    }): Promise<ResultadoGestao<unknown>> {
      const fonte = edge();
      if (!fonte) return falha({ code: "INTERNAL", message: "Gestão soberana de ciclos indisponível." });
      return projetarResultadoEdge(
        await fonte.criar({
          organizationId: entrada.organizationId,
          ano: entrada.ano,
          numero: entrada.numero,
          dataInicio: entrada.dataInicio,
          dataFim: entrada.dataFim,
          operationId: novoOperationId(),
        })
      );
    },

    async editar(entrada: {
      readonly organizationId: string;
      readonly cycleId: string;
      readonly ano: number;
      readonly numero: 1 | 2 | 3;
      readonly dataInicio: string;
      readonly dataFim: string;
      readonly expectedVersion: number;
    }): Promise<ResultadoGestao<unknown>> {
      const fonte = edge();
      if (!fonte) return falha({ code: "INTERNAL", message: "Gestão soberana de ciclos indisponível." });
      return projetarResultadoEdge(
        await fonte.editar({ ...entrada, operationId: novoOperationId() })
      );
    },

    async ativar(entrada: {
      readonly organizationId: string;
      readonly cycleId: string;
      readonly expectedVersion: number;
    }): Promise<ResultadoGestao<unknown>> {
      const fonte = edge();
      if (!fonte) return falha({ code: "INTERNAL", message: "Gestão soberana de ciclos indisponível." });
      return projetarResultadoEdge(
        await fonte.ativar({ ...entrada, operationId: novoOperationId() })
      );
    },

    async encerrar(entrada: {
      readonly organizationId: string;
      readonly cycleId: string;
      readonly expectedVersion: number;
      readonly motivo: string;
    }): Promise<ResultadoGestao<unknown>> {
      const fonte = edge();
      if (!fonte) return falha({ code: "INTERNAL", message: "Gestão soberana de ciclos indisponível." });
      return projetarResultadoEdge(
        await fonte.encerrar({ ...entrada, operationId: novoOperationId() })
      );
    },

    async cancelar(entrada: {
      readonly organizationId: string;
      readonly cycleId: string;
      readonly expectedVersion: number;
      readonly motivo: string;
    }): Promise<ResultadoGestao<unknown>> {
      const fonte = edge();
      if (!fonte) return falha({ code: "INTERNAL", message: "Gestão soberana de ciclos indisponível." });
      return projetarResultadoEdge(
        await fonte.cancelar({ ...entrada, operationId: novoOperationId() })
      );
    },

    async reabrir(entrada: {
      readonly organizationId: string;
      readonly cycleId: string;
      readonly expectedVersion: number;
      readonly motivo: string;
    }): Promise<ResultadoGestao<unknown>> {
      const fonte = edge();
      if (!fonte) return falha({ code: "INTERNAL", message: "Gestão soberana de ciclos indisponível." });
      return projetarResultadoEdge(
        await fonte.reabrir({ ...entrada, operationId: novoOperationId() })
      );
    },

    async corrigirPeriodo(entrada: {
      readonly organizationId: string;
      readonly cycleId: string;
      readonly dataInicio: string;
      readonly dataFim: string;
      readonly justificativa: string;
      readonly expectedVersion: number;
    }): Promise<ResultadoGestao<unknown>> {
      const fonte = edge();
      if (!fonte) return falha({ code: "INTERNAL", message: "Gestão soberana de ciclos indisponível." });
      return projetarResultadoEdge(
        await fonte.corrigirPeriodo({ ...entrada, operationId: novoOperationId() })
      );
    },
  };
}

export type GestaoCiclosSoberanos = ReturnType<typeof criarGestaoCiclosSoberanos>;

/** Exposto para testes de projeção/fail-closed. */
export type { CicloSoberano, ResultadoCiclos };
