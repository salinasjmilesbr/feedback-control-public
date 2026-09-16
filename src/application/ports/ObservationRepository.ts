/**
 * F5-11 P5 (Issue #250), L1 — PORTA soberana do domínio de OBSERVAÇÕES
 * (UUID-first, ASSÍNCRONA, fail-closed).
 *
 * ## Por que a porta existe
 *
 * A autoridade funcional de observações era LOCAL (`observacaoStorage` em
 * `localStorage`). A porta descreve a fronteira SOBERANA que a substitui:
 *
 * - **assíncrona**: toda operação devolve `Promise<ResultadoObservacoes<T>>`;
 * - **UUID-first**: a identidade canônica é `evaluation_observations.id` e as
 *   relações são `collaborators.id` (`collaborator_id`/`author_collaborator_id`).
 *   Matrícula, nome, `ano`/`ciclo` são RÓTULOS de projeção — nunca identidade,
 *   autorização ou chave de leitura (D1/D3);
 * - **fail-closed**: erro/indisponibilidade NUNCA resulta em fallback local,
 *   dual-read ou dado inventado. Ausência é explícita e a falha tem código
 *   público (`CodigoPublico`);
 * - **sem autorização do lado do cliente**: a porta transporta apenas INTENÇÃO
 *   (alvo, campos de domínio, motivo e `operationId`). `actor*`, `membership*`,
 *   `tenant*`, `status`, `comunicado_em`, `excluida`, `capability`, `role`,
 *   `cargo`, `funcao` e instante NÃO existem nesta superfície (D3/D7/D9/D21);
 * - **leitura pela superfície soberana (D22)**: a leitura NÃO usa PostgREST/RLS
 *   direto — `SELECT` own-tenant não é autorização funcional. Toda leitura passa
 *   por `observacao.listar_por_escopo` (escopo `SELF`/`DIRECT_REPORTS`/
 *   `DESCENDANTS`, §8 linhas 1/2) e `observacao.obter` (§8 linha 3), pelo adapter
 *   da Edge (P4).
 *
 * `operationId` é a CHAVE DE IDEMPOTÊNCIA do contrato (D10/D11), gerada quando
 * ausente — repetir a MESMA intenção com o mesmo id é seguro. Não é identidade
 * de observação.
 *
 * `expectedVersion` é OBRIGATÓRIO nas mutações de LINHA EXISTENTE (D10): ele é
 * SEMPRE derivado da LEITURA soberana (por `obterObservacao`) — o chamador da
 * porta (o controlador) o obtém da leitura, nunca do usuário/browser.
 *
 * O que esta porta NÃO faz: autoria (D5), verificação de ciclo/estado (D11/D12),
 * relação/escopo (a RPC decide), comparação de versão, transação, auditoria e
 * autorização. Tudo isso pertence às RPCs soberanas (§20/§21), pelas quais a Edge
 * é a única via.
 */

import type {
  CodigoPublico,
  EscopoObservacao,
  TipoEventoObservacao,
  TipoObservacaoSoberana,
} from "../../infrastructure/supabase/observacoes/contrato";

/** Erro público: código estável + mensagem sem detalhe do banco. */
export interface ErroObservacoesSoberanas {
  readonly code: CodigoPublico;
  readonly message: string;
}

/** Resultado da porta: sucesso com dados ou falha com código público. */
export type ResultadoObservacoes<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: ErroObservacoesSoberanas };

/**
 * Projeção soberana de UMA observação (`observacao_obter`/`itens` de
 * `observacao_listar_por_escopo`): exatamente os campos da projeção da RPC da P2
 * — nada é inventado (sem matrícula, nome, `ano`/`ciclo` ou histórico local).
 *
 * Identidades são UUID: `collaboratorId` (colaborador-ALVO da observação),
 * `autorUserProfileId` (`author_user_profile_id`) e `autorCollaboratorId`
 * (`author_collaborator_id`, anulável por schema).
 */
export interface ObservacaoSoberana {
  readonly id: string;
  readonly organizationId: string;
  readonly collaboratorId: string;
  readonly cycleId: string;
  readonly tipo: TipoObservacaoSoberana;
  readonly texto: string;
  readonly comunicado: boolean;
  /** Data soberana da comunicação; `null` = nunca comunicada. */
  readonly comunicadoEm: string | null;
  readonly excluida: boolean;
  /** Motivo da exclusão lógica; `null` = sem exclusão registrada. */
  readonly motivoExclusao: string | null;
  readonly autorUserProfileId: string;
  readonly autorCollaboratorId: string | null;
  /** Versão otimista da linha (base de `expectedVersion` — D10). */
  readonly version: number;
  readonly criadoEm: string;
  readonly atualizadoEm: string;
}

/**
 * Recorte soberano da leitura por escopo (§8 linhas 1/2): o ator recebe SOMENTE
 * as observações autorizadas para o escopo pedido. Conjunto vazio é ausência
 * EXPLÍCITA de observação autorizada — nunca negação silenciosa.
 *
 * `selfCollaboratorId` é o vínculo soberano do ator (fato da RPC, não do
 * cliente) e `data` é o instante SOBERANO usado na resolução do escopo (D21).
 */
export interface EscopoObservacoesSoberanas {
  readonly escopo: EscopoObservacao;
  readonly selfCollaboratorId: string | null;
  readonly data: string;
  readonly total: number;
  readonly itens: readonly ObservacaoSoberana[];
}

/** Observação mutada: fatos da RPC que a projeção admite como contrato. */
export interface ObservacaoMutadaSoberana {
  readonly observacaoId: string;
  readonly version: number;
}

/**
 * Evento da TRILHA append-only da observação (D6), exatamente a projeção de
 * `observacao_historico` (P2) — nada é inventado aqui: não há `ano`/`ciclo`,
 * matrícula, nome ou "ação" textual derivada de UUID.
 *
 * Identidades são UUID: `actorUserProfileId` (`actor_user_profile_id`) e
 * `actorCollaboratorId` (`actor_collaborator_id`, ANULÁVEL por schema — a coluna
 * não existe na projeção da trilha, logo o campo é `null` até que uma superfície
 * soberana o forneça; nunca é preenchido por inferência).
 *
 * `beforeValue`/`afterValue` são a imagem JSON crua da linha (as chaves variam
 * por `evento`: `CRIADA`/`EDITADA` trazem tipo/texto/comunicado/excluida/version;
 * `COMUNICADO`/`COMUNICACAO_REMOVIDA` trazem comunicado/comunicado_em/version;
 * `EXCLUIDA`/`REVOGADA` trazem excluida/motivo_exclusao/version). A projeção não
 * normaliza a forma — quem interpreta é o mapeador de UI, por `evento`.
 */
export interface EventoHistoricoSoberano {
  readonly id: string;
  readonly evento: TipoEventoObservacao;
  /** Instante EFETIVO do fato, gravado pelo servidor (`effective_date`). */
  readonly dataEfetiva: string;
  /** Motivo do fato; `null` = evento sem motivo registrado. */
  readonly motivo: string | null;
  readonly beforeValue: Readonly<Record<string, unknown>> | null;
  readonly afterValue: Readonly<Record<string, unknown>> | null;
  /** SHA-256 hex da intenção canônica, derivado server-side (D6). */
  readonly payloadHash: string;
  readonly actorUserProfileId: string;
  /** Ator sem vínculo de colaborador é `null` na linha — nunca inventado. */
  readonly actorCollaboratorId: string | null;
  /** Chave de idempotência da operação que produziu o evento (D6/D10). */
  readonly operationId: string;
  readonly criadoEm: string;
}

/**
 * Trilha soberana de UMA observação (`observacao_historico`): a MESMA
 * visibilidade de `obter` (§8 linha 10 — a trilha não amplia alcance).
 * `total` é o fato da RPC; `eventos` é a projeção (linha fora do contrato é
 * DESCARTADA, nunca completada).
 */
export interface HistoricoObservacaoSoberana {
  readonly observacaoId: string;
  readonly total: number;
  readonly eventos: readonly EventoHistoricoSoberano[];
}

/** Chave de idempotência OPCIONAL (gerada pelo adaptador quando ausente — D10). */
export interface OperacaoIdempotente {
  readonly operationId?: string;
}

/** `observacao.criar`: o alvo é INTENÇÃO; relação/autoria são revalidadas server-side. */
export interface NovaObservacaoSoberana extends OperacaoIdempotente {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly collaboratorId: string;
  readonly tipo: TipoObservacaoSoberana;
  readonly texto: string;
}

/** Opções da leitura por escopo: unidade (opcional) e idempotência. */
export interface OpcoesLeituraPorEscopo extends OperacaoIdempotente {
  readonly organizationalUnitId?: string;
}

/** Leitura de UMA observação (por UUID). */
export interface LeituraObservacaoSoberana extends OperacaoIdempotente {
  readonly organizationId: string;
  readonly observationId: string;
}

/** Leitura da TRILHA de UMA observação (por UUID — `observacao.historico`). */
export interface LeituraHistoricoSoberana extends OperacaoIdempotente {
  readonly organizationId: string;
  readonly observationId: string;
}

/** `observacao.editar`: definição COMPLETA (não há edição parcial — sem merge local). */
export interface EdicaoObservacaoSoberana extends LeituraObservacaoSoberana {
  readonly tipo: TipoObservacaoSoberana;
  readonly texto: string;
  readonly comunicado: boolean;
  readonly expectedVersion: number;
}

/** `observacao.definir_comunicado` (§8 linhas 6/7; D7). */
export interface ComunicadoObservacaoSoberana extends LeituraObservacaoSoberana {
  readonly comunicado: boolean;
  readonly expectedVersion: number;
}

/** `observacao.excluir` (§8 linha 8; motivo OBRIGATÓRIO). */
export interface ExclusaoObservacaoSoberana extends LeituraObservacaoSoberana {
  readonly motivo: string;
  readonly expectedVersion: number;
}

/** `observacao.revogar` (§8 linha 9; motivo OBRIGATÓRIO). */
export interface RevogacaoObservacaoSoberana extends LeituraObservacaoSoberana {
  readonly motivo: string;
  readonly expectedVersion: number;
}

/**
 * Porta única do domínio de observações: LEITURA por escopo/por observação e
 * MUTAÇÕES soberanas.
 *
 * Sem estado, sem cache e sem autorização: a organização é INTENÇÃO de UX e a
 * decisão é sempre da fronteira (Edge `observacoes`) — a implementação
 * atravessa EXCLUSIVAMENTE o adapter da Edge, nunca tabela/RLS direta.
 */
export interface ObservationRepository {
  /** Observações autorizadas do escopo pedido (`observacao.listar_por_escopo`). */
  listarObservacoesPorEscopo(
    organizationId: string,
    escopo: EscopoObservacao,
    opcoes?: OpcoesLeituraPorEscopo
  ): Promise<ResultadoObservacoes<EscopoObservacoesSoberanas>>;
  /** Uma observação por UUID (`observacao.obter`) — visibilidade soberana. */
  obterObservacao(
    dados: LeituraObservacaoSoberana
  ): Promise<ResultadoObservacoes<ObservacaoSoberana>>;
  /**
   * TRILHA append-only de uma observação (`observacao.historico`) — a única
   * fonte do histórico (D6). A visibilidade é a MESMA de `obter` (§8 linha 10).
   */
  obterHistoricoObservacao(
    dados: LeituraHistoricoSoberana
  ): Promise<ResultadoObservacoes<HistoricoObservacaoSoberana>>;
  criarObservacao(dados: NovaObservacaoSoberana): Promise<ResultadoObservacoes<ObservacaoMutadaSoberana>>;
  editarObservacao(dados: EdicaoObservacaoSoberana): Promise<ResultadoObservacoes<ObservacaoMutadaSoberana>>;
  definirComunicado(
    dados: ComunicadoObservacaoSoberana
  ): Promise<ResultadoObservacoes<ObservacaoMutadaSoberana>>;
  excluirObservacao(
    dados: ExclusaoObservacaoSoberana
  ): Promise<ResultadoObservacoes<ObservacaoMutadaSoberana>>;
  revogarExclusao(
    dados: RevogacaoObservacaoSoberana
  ): Promise<ResultadoObservacoes<ObservacaoMutadaSoberana>>;
}
