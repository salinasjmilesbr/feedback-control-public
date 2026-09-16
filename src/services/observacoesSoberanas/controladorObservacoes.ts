/**
 * F5-11 P5 (Issue #250), L2 — CONTROLADOR de observações soberanas.
 *
 * Responsabilidades (e nada além):
 * - **idempotência (D10):** gera `operationId` por operação; repetir a mesma
 *   intenção com o mesmo id é seguro;
 * - **`expectedVersion` da LEITURA (D10):** toda mutação de linha existente lê
 *   PRIMEIRO a observação pela superfície soberana e usa a `version` lida. O
 *   usuário/browser NUNCA declara versão;
 * - **tradução de erro → mensagem de UI:** o `CodigoPublico` da porta ganha
 *   mensagem estável; código sem mensagem específica cai numa mensagem genérica
 *   (fail-closed, nunca "sucesso" e nunca detalhe do banco);
 * - **nenhuma autoridade transportada:** o controlador só envia intenção
 *   (organização, UUIDs de alvo, campos de domínio e motivo). `actor*`,
 *   `membership*`, autoria, `status`, `comunicado_em`, `excluida`, capability e
 *   instante NÃO existem nesta superfície (D3/D7/D9/D21).
 *
 * O controlador NÃO decide autorização, NÃO resolve identidade (matrícula/nome)
 * e NÃO faz fallback local: a decisão é da Edge/RPC; a apresentação é do
 * mapeador de UI, que recebe rótulos por parâmetro.
 */

import type {
  EscopoObservacoesSoberanas,
  HistoricoObservacaoSoberana,
  ObservacaoMutadaSoberana,
  ObservacaoSoberana,
  ObservationRepository,
  ResultadoObservacoes,
} from "../../application/ports/ObservationRepository";
import type { CodigoPublico, EscopoObservacao, TipoObservacaoSoberana } from "../../infrastructure/supabase/observacoes/contrato";

/** Falha de UI: código público estável + mensagem apresentável. */
export interface FalhaObservacoesUi {
  readonly code: CodigoPublico;
  readonly mensagem: string;
}

/** Resultado de UI: sucesso com dado soberano ou falha com mensagem. */
export type ResultadoObservacoesUi<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: FalhaObservacoesUi };

const MENSAGEM_GENERICA = "Não foi possível concluir a operação. Tente novamente.";

const MENSAGENS: Partial<Record<CodigoPublico, string>> = {
  NOT_AUTHORIZED: "Sua sessão expirou. Entre novamente para continuar.",
  FORBIDDEN: "Você não tem permissão para esta operação.",
  NOT_FOUND: "Observação não encontrada.",
  CONFLICT:
    "A observação mudou desde que você a abriu. Recarregue os dados e tente novamente.",
  INVALID_INPUT: "Dados inválidos. Revise os campos e tente novamente.",
  INTERNAL: "Erro inesperado ao falar com o servidor. Tente novamente.",
};

function mensagemDe(code: CodigoPublico): string {
  return MENSAGENS[code] ?? MENSAGEM_GENERICA;
}

function falhaDe<T>(erro: { readonly code: CodigoPublico }): ResultadoObservacoesUi<T> {
  return { ok: false, error: { code: erro.code, mensagem: mensagemDe(erro.code) } };
}

function traduzir<T>(resultado: ResultadoObservacoes<T>): ResultadoObservacoesUi<T> {
  return resultado.ok ? { ok: true, data: resultado.data } : falhaDe<T>(resultado.error);
}

/** Intenção de CRIAÇÃO (UUID-first; ciclo e colaborador-alvo são obrigatórios). */
export interface IntencaoCriarObservacao {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly collaboratorId: string;
  readonly tipo: TipoObservacaoSoberana;
  readonly texto: string;
}

/** Intenção de EDIÇÃO (definição COMPLETA — sem merge local). */
export interface IntencaoEditarObservacao {
  readonly organizationId: string;
  readonly observationId: string;
  readonly tipo: TipoObservacaoSoberana;
  readonly texto: string;
  readonly comunicado: boolean;
}

/** Intenção de comunicação/descomunicação (D7). */
export interface IntencaoComunicarObservacao {
  readonly organizationId: string;
  readonly observationId: string;
  readonly comunicado: boolean;
}

/** Intenção com motivo OBRIGATÓRIO (excluir/revogar — §8 linhas 8/9). */
export interface IntencaoComMotivo {
  readonly organizationId: string;
  readonly observationId: string;
  readonly motivo: string;
}

export interface DepsControladorObservacoes {
  /** Porta soberana (exclusivamente Edge/RPC — nunca tabela, nunca storage local). */
  readonly repositorio: ObservationRepository;
  /** Gerador de chave de idempotência (injetável para teste); padrão UUID v4. */
  readonly gerarOperationId?: () => string;
}

export interface ControladorObservacoes {
  listarPorEscopo(
    organizationId: string,
    escopo: EscopoObservacao,
    opcoes?: { readonly organizationalUnitId?: string }
  ): Promise<ResultadoObservacoesUi<EscopoObservacoesSoberanas>>;
  obter(
    organizationId: string,
    observationId: string
  ): Promise<ResultadoObservacoesUi<ObservacaoSoberana>>;
  /**
   * TRILHA append-only da observação (§8 linha 10/D6): a timeline SOBERANA do
   * painel. Mesma visibilidade de `obter` — a trilha não amplia alcance.
   */
  historico(
    organizationId: string,
    observationId: string
  ): Promise<ResultadoObservacoesUi<HistoricoObservacaoSoberana>>;
  criar(dados: IntencaoCriarObservacao): Promise<ResultadoObservacoesUi<ObservacaoMutadaSoberana>>;
  editar(dados: IntencaoEditarObservacao): Promise<ResultadoObservacoesUi<ObservacaoMutadaSoberana>>;
  definirComunicado(
    dados: IntencaoComunicarObservacao
  ): Promise<ResultadoObservacoesUi<ObservacaoMutadaSoberana>>;
  excluir(dados: IntencaoComMotivo): Promise<ResultadoObservacoesUi<ObservacaoMutadaSoberana>>;
  revogar(dados: IntencaoComMotivo): Promise<ResultadoObservacoesUi<ObservacaoMutadaSoberana>>;
}

export function criarControladorObservacoes(
  deps: DepsControladorObservacoes
): ControladorObservacoes {
  const novoId = (): string =>
    deps.gerarOperationId ? deps.gerarOperationId() : globalThis.crypto.randomUUID();

  /**
   * Mutações de LINHA EXISTENTE: a versão vem SEMPRE da leitura soberana desta
   * mesma chamada (D10). Negação na leitura interrompe ANTES de qualquer mutação
   * — não existe tentativa otimista com versão inventada.
   */
  async function comVersaoLida(
    organizationId: string,
    observationId: string,
    mutar: (expectedVersion: number) => Promise<ResultadoObservacoes<ObservacaoMutadaSoberana>>
  ): Promise<ResultadoObservacoesUi<ObservacaoMutadaSoberana>> {
    const leitura = await deps.repositorio.obterObservacao({
      organizationId,
      observationId,
      operationId: novoId(),
    });
    if (!leitura.ok) return falhaDe<ObservacaoMutadaSoberana>(leitura.error);
    return traduzir(await mutar(leitura.data.version));
  }

  return {
    async listarPorEscopo(organizationId, escopo, opcoes) {
      return traduzir(
        await deps.repositorio.listarObservacoesPorEscopo(organizationId, escopo, {
          ...(opcoes?.organizationalUnitId
            ? { organizationalUnitId: opcoes.organizationalUnitId }
            : {}),
          operationId: novoId(),
        })
      );
    },

    async obter(organizationId, observationId) {
      return traduzir(
        await deps.repositorio.obterObservacao({
          organizationId,
          observationId,
          operationId: novoId(),
        })
      );
    },

    async historico(organizationId, observationId) {
      return traduzir(
        await deps.repositorio.obterHistoricoObservacao({
          organizationId,
          observationId,
          operationId: novoId(),
        })
      );
    },

    async criar(dados) {
      return traduzir(
        await deps.repositorio.criarObservacao({
          organizationId: dados.organizationId,
          cycleId: dados.cycleId,
          collaboratorId: dados.collaboratorId,
          tipo: dados.tipo,
          texto: dados.texto,
          operationId: novoId(),
        })
      );
    },

    async editar(dados) {
      return comVersaoLida(dados.organizationId, dados.observationId, (expectedVersion) =>
        deps.repositorio.editarObservacao({
          organizationId: dados.organizationId,
          observationId: dados.observationId,
          tipo: dados.tipo,
          texto: dados.texto,
          comunicado: dados.comunicado,
          expectedVersion,
          operationId: novoId(),
        })
      );
    },

    async definirComunicado(dados) {
      return comVersaoLida(dados.organizationId, dados.observationId, (expectedVersion) =>
        deps.repositorio.definirComunicado({
          organizationId: dados.organizationId,
          observationId: dados.observationId,
          comunicado: dados.comunicado,
          expectedVersion,
          operationId: novoId(),
        })
      );
    },

    async excluir(dados) {
      return comVersaoLida(dados.organizationId, dados.observationId, (expectedVersion) =>
        deps.repositorio.excluirObservacao({
          organizationId: dados.organizationId,
          observationId: dados.observationId,
          motivo: dados.motivo,
          expectedVersion,
          operationId: novoId(),
        })
      );
    },

    async revogar(dados) {
      return comVersaoLida(dados.organizationId, dados.observationId, (expectedVersion) =>
        deps.repositorio.revogarExclusao({
          organizationId: dados.organizationId,
          observationId: dados.observationId,
          motivo: dados.motivo,
          expectedVersion,
          operationId: novoId(),
        })
      );
    },
  };
}
