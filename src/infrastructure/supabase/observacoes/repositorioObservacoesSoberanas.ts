/**
 * F5-11 P5 (Issue #250), L1 — implementação da PORTA de observações
 * EXCLUSIVAMENTE sobre o adapter da Edge (`edgeObservacoes`, entregue na P4).
 *
 * ## D22 — a leitura também é soberana pela Edge
 *
 * Este repositório NÃO acessa tabela alguma: **todas** as operações do port —
 * leitura inclusive — atravessam a superfície soberana (`observacao.listar_por_escopo`,
 * `observacao.obter` e as mutações do contrato). Motivo: `SELECT` own-tenant sob
 * RLS é barreira de TENANT, **não** autorização funcional (§8 invariante 3).
 *
 * Consequências (fail-closed por construção):
 * - nenhum `SupabaseClient` de tabela é importado, nenhum `.from(...)` e nenhuma
 *   RPC é chamada deste lado; nenhum `localStorage`/`sessionStorage`, nenhum
 *   cache e nenhum dual-read (D13);
 * - falha de transporte/autorização vira erro com código público — nunca "lista
 *   vazia" por negação silenciosa;
 * - a projeção NÃO inventa campos: linha fora do contrato é DESCARTADA e
 *   envelope fora do contrato é `INTERNAL` (resposta anômala nunca é apresentada
 *   como ausência de observações);
 * - `operationId` é chave de IDEMPOTÊNCIA (D10): pode vir do chamador
 *   (retentativa segura) ou ser gerado aqui quando ausente.
 *
 * ## Limite de projeção (fato do SQL da P2, não suposição)
 *
 * `observacao_obter` devolve `organization_id` e `motivo_exclusao`; os itens de
 * `observacao_listar_por_escopo` NÃO devolvem essas duas colunas (e a listagem
 * filtra `not excluida` nos escopos de gestão e `comunicado and not excluida` no
 * SELF). Por isso a projeção recebe o contexto de origem: em `obter` o tenant e o
 * motivo vêm da LINHA; na listagem o tenant é o da própria requisição (o mesmo
 * que a Edge revalidou) e `motivoExclusao` é `null` porque o FATO não está na
 * projeção daquela operação — nunca porque foi "assumido".
 *
 * A TRILHA (`observacao.historico`) entrou no L3 sobre a MESMA fronteira: a
 * projeção é a da RPC `observacao_historico` (motivo, imagem before/after,
 * `payload_hash`, ator e instante efetivos), sem inventar `ano`/`ciclo`,
 * matrícula, nome ou "ação" textual derivada de UUID.
 */

import type {
  ComunicadoObservacaoSoberana,
  EdicaoObservacaoSoberana,
  EscopoObservacoesSoberanas,
  EventoHistoricoSoberano,
  ExclusaoObservacaoSoberana,
  HistoricoObservacaoSoberana,
  LeituraHistoricoSoberana,
  LeituraObservacaoSoberana,
  NovaObservacaoSoberana,
  ObservacaoMutadaSoberana,
  ObservacaoSoberana,
  ObservationRepository,
  OpcoesLeituraPorEscopo,
  ResultadoObservacoes,
  RevogacaoObservacaoSoberana,
} from "../../../application/ports/ObservationRepository";
import {
  ehUuid,
  ESCOPOS_OBSERVACAO,
  TIPOS_EVENTO_OBSERVACAO,
  TIPOS_OBSERVACAO,
  type CodigoPublico,
  type EscopoObservacao,
  type TipoEventoObservacao,
  type TipoObservacaoSoberana,
} from "./contrato";
import type { EdgeObservacoes, ResultadoEdgeObservacoes } from "./edgeObservacoes";

const ERRO_RESPOSTA = "Resposta inesperada do servidor.";

function ehRegistro(valor: unknown): valor is Record<string, unknown> {
  return typeof valor === "object" && valor !== null && !Array.isArray(valor);
}

function ehTexto(valor: unknown): valor is string {
  return typeof valor === "string";
}

function ehVersao(valor: unknown): valor is number {
  return typeof valor === "number" && Number.isInteger(valor) && valor >= 0;
}

function ehTipo(valor: unknown): valor is TipoObservacaoSoberana {
  return typeof valor === "string" && (TIPOS_OBSERVACAO as readonly string[]).includes(valor);
}

function ehEscopo(valor: unknown): valor is EscopoObservacao {
  return typeof valor === "string" && (ESCOPOS_OBSERVACAO as readonly string[]).includes(valor);
}

/** Texto possivelmente nulo (coluna anulável): `undefined` = fora do contrato. */
function textoOuNulo(valor: unknown): string | null | undefined {
  if (valor === null) return null;
  return ehTexto(valor) ? valor : undefined;
}

/** UUID possivelmente nulo (identidade soberana): `undefined` = fora do contrato. */
function uuidOuNulo(valor: unknown): string | null | undefined {
  if (valor === null) return null;
  return ehUuid(valor) ? valor.trim() : undefined;
}

/** Contexto de origem da projeção (ver cabeçalho: `obter` × listagem). */
interface OrigemProjecao {
  readonly organizationId: string;
  /** `true` em `observacao_obter`, cuja projeção traz `organization_id`. */
  readonly comTenantNaLinha: boolean;
}

/**
 * Projeta UMA observação da projeção real da P2. Qualquer campo obrigatório fora
 * do contrato ⇒ `null` (linha DESCARTADA; nunca normalizada nem completada).
 */
function projetarObservacao(
  valor: unknown,
  origem: OrigemProjecao
): ObservacaoSoberana | null {
  if (!ehRegistro(valor)) return null;

  const id = valor.observation_id;
  if (!ehUuid(id)) return null;

  const collaboratorId = valor.collaborator_id;
  const cycleId = valor.cycle_id;
  const autorUserProfileId = valor.author_user_profile_id;
  if (!ehUuid(collaboratorId) || !ehUuid(cycleId) || !ehUuid(autorUserProfileId)) return null;
  if (!ehTipo(valor.tipo)) return null;
  if (!ehTexto(valor.texto)) return null;
  if (typeof valor.comunicado !== "boolean") return null;
  if (typeof valor.excluida !== "boolean") return null;
  if (!ehVersao(valor.version)) return null;
  if (!ehTexto(valor.created_at) || !ehTexto(valor.updated_at)) return null;

  const comunicadoEm = textoOuNulo(valor.comunicado_em);
  if (comunicadoEm === undefined) return null;

  const autorCollaboratorId = uuidOuNulo(valor.author_collaborator_id);
  if (autorCollaboratorId === undefined) return null;

  let organizationId = origem.organizationId;
  if (origem.comTenantNaLinha) {
    const tenantDaLinha = valor.organization_id;
    if (!ehUuid(tenantDaLinha)) return null;
    organizationId = tenantDaLinha.trim();
  }

  let motivoExclusao: string | null = null;
  if (origem.comTenantNaLinha) {
    const motivo = textoOuNulo(valor.motivo_exclusao);
    if (motivo === undefined) return null;
    motivoExclusao = motivo;
  }

  return {
    id: id.trim(),
    organizationId,
    collaboratorId: collaboratorId.trim(),
    cycleId: cycleId.trim(),
    tipo: valor.tipo,
    texto: valor.texto,
    comunicado: valor.comunicado,
    comunicadoEm,
    excluida: valor.excluida,
    motivoExclusao,
    autorUserProfileId: autorUserProfileId.trim(),
    autorCollaboratorId,
    version: valor.version,
    criadoEm: valor.created_at,
    atualizadoEm: valor.updated_at,
  };
}

/** Projeta o recorte da leitura por escopo (envelope da P2). */
function projetarEscopo(
  valor: unknown,
  organizationId: string
): EscopoObservacoesSoberanas | null {
  if (!ehRegistro(valor)) return null;
  if (!ehEscopo(valor.escopo)) return null;

  const selfCollaboratorId = uuidOuNulo(valor.self_collaborator_id);
  if (selfCollaboratorId === undefined) return null;
  if (!ehTexto(valor.data)) return null;
  if (!ehVersao(valor.total)) return null;
  if (!Array.isArray(valor.itens)) return null;

  const itens: ObservacaoSoberana[] = [];
  for (const item of valor.itens) {
    const projetada = projetarObservacao(item, {
      organizationId,
      comTenantNaLinha: false,
    });
    // Linha fora do contrato é DESCARTADA (nunca completada com valor inventado).
    if (projetada) itens.push(projetada);
  }

  return {
    escopo: valor.escopo,
    selfCollaboratorId,
    data: valor.data,
    total: valor.total,
    itens,
  };
}

/** Projeta o resultado de uma mutação (`observation_id` + `version` são contrato). */
function projetarMutacao(valor: unknown): ObservacaoMutadaSoberana | null {
  if (!ehRegistro(valor)) return null;
  const observacaoId = valor.observation_id;
  if (!ehUuid(observacaoId)) return null;
  if (!ehVersao(valor.version)) return null;
  return { observacaoId: observacaoId.trim(), version: valor.version };
}

function ehTipoEvento(valor: unknown): valor is TipoEventoObservacao {
  return (
    typeof valor === "string" && (TIPOS_EVENTO_OBSERVACAO as readonly string[]).includes(valor)
  );
}

/**
 * Imagem JSON do evento (`before_value`/`after_value`). Um registro é aceito como
 * está; `null` é o FATO "sem imagem" (a criação não tem before); qualquer outra
 * forma (array, escalar) está FORA do contrato e descarta a linha.
 */
function imagemOuNulo(valor: unknown): Readonly<Record<string, unknown>> | null | undefined {
  if (valor === null) return null;
  return ehRegistro(valor) ? valor : undefined;
}

/**
 * Projeta UM evento da trilha a partir da projeção REAL de `observacao_historico`
 * (P2): `event_id`, `event_type`, `effective_date`, `reason`, `before_value`,
 * `after_value`, `payload_hash`, `actor_user_profile_id`, `operation_id` e
 * `created_at`.
 *
 * A projeção NÃO traz `actor_collaborator_id`: o campo é `null` — jamais inferido
 * do perfil, da membership ou do UUID. Evento fora do contrato ⇒ `null`
 * (descartado, nunca completado).
 */
function projetarEvento(valor: unknown): EventoHistoricoSoberano | null {
  if (!ehRegistro(valor)) return null;

  const id = valor.event_id;
  if (!ehUuid(id)) return null;

  if (!ehTipoEvento(valor.event_type)) return null;
  if (!ehTexto(valor.effective_date)) return null;

  const motivo = textoOuNulo(valor.reason);
  if (motivo === undefined) return null;

  const beforeValue = imagemOuNulo(valor.before_value);
  if (beforeValue === undefined) return null;
  const afterValue = imagemOuNulo(valor.after_value);
  if (afterValue === undefined) return null;

  if (!ehTexto(valor.payload_hash)) return null;
  if (!ehUuid(valor.actor_user_profile_id)) return null;
  if (!ehUuid(valor.operation_id)) return null;
  if (!ehTexto(valor.created_at)) return null;

  return {
    id: id.trim(),
    evento: valor.event_type,
    dataEfetiva: valor.effective_date,
    motivo,
    beforeValue,
    afterValue,
    payloadHash: valor.payload_hash,
    actorUserProfileId: valor.actor_user_profile_id.trim(),
    actorCollaboratorId: null,
    operationId: valor.operation_id.trim(),
    criadoEm: valor.created_at,
  };
}

/**
 * Projeta o envelope da trilha. Envelope sem `total`/`eventos` ou com
 * `observation_id` divergente do alvo pedido está fora do contrato ⇒ `null`
 * (resposta anômala nunca é apresentada como histórico vazio).
 */
function projetarHistorico(
  valor: unknown,
  observationId: string
): HistoricoObservacaoSoberana | null {
  if (!ehRegistro(valor)) return null;

  const alvo = valor.observation_id;
  if (!ehUuid(alvo) || alvo.trim() !== observationId) return null;
  if (!ehVersao(valor.total)) return null;
  if (!Array.isArray(valor.eventos)) return null;

  const eventos: EventoHistoricoSoberano[] = [];
  for (const item of valor.eventos) {
    const projetado = projetarEvento(item);
    // Evento fora do contrato é DESCARTADO (nunca completado nem traduzido).
    if (projetado) eventos.push(projetado);
  }

  return { observacaoId: observationId, total: valor.total, eventos };
}

/**
 * Converte o resultado do adapter no resultado da porta.
 *
 * O adapter já é fail-closed nos três caminhos; aqui só há DUAS decisões: (a)
 * propaga-se o erro público SEM tocar no dado; (b) o payload de sucesso é
 * projetado — forma fora do contrato vira `INTERNAL`, nunca dado inventado.
 */
function converter<T>(
  resultado: ResultadoEdgeObservacoes<unknown>,
  projetar: (valor: unknown) => T | null
): ResultadoObservacoes<T> {
  if (!resultado.ok) {
    return {
      ok: false,
      error: { code: resultado.error.code as CodigoPublico, message: resultado.error.message },
    };
  }
  const projetado = projetar(resultado.data);
  if (projetado === null) {
    return { ok: false, error: { code: "INTERNAL", message: ERRO_RESPOSTA } };
  }
  return { ok: true, data: projetado };
}

/** `operationId` do chamador (retentativa segura) ou um novo (D10). */
function idempotencia(valor?: string): string {
  const limpo = typeof valor === "string" ? valor.trim() : "";
  return limpo.length > 0 ? limpo : globalThis.crypto.randomUUID();
}

/**
 * Cria o repositório sobre o adapter da Edge. A Edge é injetada (nada de cliente
 * de tabela aqui) — a construção concreta do `SupabaseClient` fica na borda da
 * aplicação, como no adapter da P4.
 */
export function criarRepositorioObservacoesSoberanas(
  edge: EdgeObservacoes
): ObservationRepository {
  return {
    async listarObservacoesPorEscopo(
      organizationId: string,
      escopo: EscopoObservacao,
      opcoes?: OpcoesLeituraPorEscopo
    ) {
      const resultado = await edge.listarPorEscopo({
        organizationId,
        escopo,
        ...(opcoes?.organizationalUnitId
          ? { organizationalUnitId: opcoes.organizationalUnitId }
          : {}),
        operationId: idempotencia(opcoes?.operationId),
      });
      return converter(resultado, (valor) => projetarEscopo(valor, organizationId));
    },

    async obterObservacao(dados: LeituraObservacaoSoberana) {
      const resultado = await edge.obter({
        organizationId: dados.organizationId,
        observationId: dados.observationId,
        operationId: idempotencia(dados.operationId),
      });
      return converter(resultado, (valor) =>
        projetarObservacao(valor, {
          organizationId: dados.organizationId,
          comTenantNaLinha: true,
        })
      );
    },

    async obterHistoricoObservacao(dados: LeituraHistoricoSoberana) {
      const resultado = await edge.historico({
        organizationId: dados.organizationId,
        observationId: dados.observationId,
        operationId: idempotencia(dados.operationId),
      });
      return converter(resultado, (valor) =>
        projetarHistorico(valor, dados.observationId)
      );
    },

    async criarObservacao(dados: NovaObservacaoSoberana) {
      const resultado = await edge.criar({
        organizationId: dados.organizationId,
        cycleId: dados.cycleId,
        collaboratorId: dados.collaboratorId,
        tipo: dados.tipo,
        texto: dados.texto,
        operationId: idempotencia(dados.operationId),
      });
      return converter(resultado, projetarMutacao);
    },

    async editarObservacao(dados: EdicaoObservacaoSoberana) {
      const resultado = await edge.editar({
        organizationId: dados.organizationId,
        observationId: dados.observationId,
        tipo: dados.tipo,
        texto: dados.texto,
        comunicado: dados.comunicado,
        expectedVersion: dados.expectedVersion,
        operationId: idempotencia(dados.operationId),
      });
      return converter(resultado, projetarMutacao);
    },

    async definirComunicado(dados: ComunicadoObservacaoSoberana) {
      const resultado = await edge.definirComunicado({
        organizationId: dados.organizationId,
        observationId: dados.observationId,
        comunicado: dados.comunicado,
        expectedVersion: dados.expectedVersion,
        operationId: idempotencia(dados.operationId),
      });
      return converter(resultado, projetarMutacao);
    },

    async excluirObservacao(dados: ExclusaoObservacaoSoberana) {
      const resultado = await edge.excluir({
        organizationId: dados.organizationId,
        observationId: dados.observationId,
        motivo: dados.motivo,
        expectedVersion: dados.expectedVersion,
        operationId: idempotencia(dados.operationId),
      });
      return converter(resultado, projetarMutacao);
    },

    async revogarExclusao(dados: RevogacaoObservacaoSoberana) {
      const resultado = await edge.revogar({
        organizationId: dados.organizationId,
        observationId: dados.observationId,
        motivo: dados.motivo,
        expectedVersion: dados.expectedVersion,
        operationId: idempotencia(dados.operationId),
      });
      return converter(resultado, projetarMutacao);
    },
  };
}
