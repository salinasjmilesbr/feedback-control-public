/**
 * F5-10 P5 (Issue #218), Bloco 1/S2 — implementação da PORTA de metas
 * EXCLUSIVAMENTE sobre o adapter da Edge (`edgeMetas`).
 *
 * ## D22-A — a leitura também é soberana pela Edge (decisão do Bloco 1)
 *
 * Ao contrário de `repositorioCiclosSoberanos` (que lê por PostgREST + RLS), este
 * repositório NÃO acessa tabela alguma: **todas** as operações do port — leitura
 * inclusive — atravessam a superfície soberana, por `goal.listar_por_escopo` e
 * pelas demais operações do contrato. Motivo: `SELECT` own-tenant sob RLS é
 * barreira de TENANT, **não** autorização funcional (§11) — quem responde "esta
 * identidade pode LER ESTA meta?" é o Policy Engine, acessível apenas pela Edge.
 * Por D22-A, a autorização funcional de leitura passa exclusivamente pela
 * superfície soberana, e a RLS de metas será revogada para `authenticated` no
 * Bloco 2 desta mesma Issue (#218).
 *
 * Consequências (fail-closed por construção):
 * - nenhum `SupabaseClient` de tabela é importado, nenhum `.from("evaluation_goals")`
 *   e nenhuma RPC é chamada deste lado;
 * - não existe fallback local (`localStorage`, cache, dual-read) nem "lista
 *   vazia" por negação silenciosa: falha de transporte/autorização vira erro
 *   com código público;
 * - a projeção não inventa campos: linha fora do contrato é DESCARTADA e
 *   envelope fora do contrato é `INTERNAL` (resposta anômala nunca é apresentada
 *   como ausência de metas);
 * - `operationId` é chave de IDEMPOTÊNCIA (D11): pode ser fornecido pelo
 *   chamador (retentativa segura) ou gerado aqui quando ausente.
 *
 * ## P5.2 (Issue #222) — projeção AMPLIADA, sem nova superfície
 *
 * A P5.2 é estritamente ADITIVA na PROJEÇÃO (§3/§4/§5 do contrato): datas
 * soberanas da linha, `aprovacoes[]` por papel e `limites[]` do ciclo. A
 * superfície de métodos, os gates, o `operationId` e a lista de operações NÃO
 * mudam (§6). Os campos novos seguem a MESMA disciplina fail-closed: forma
 * inesperada é contrato violado — linha descartada (metas) ou `INTERNAL`
 * (envelope), nunca normalizada, nunca completada com valor inventado.
 */

import type {
  AprovacaoMetaSolicitada,
  AprovacaoRegistradaSoberana,
  AprovacaoSoberana,
  AprovacaoVigenteSoberana,
  DefinicaoDeLimitesDoSoberana,
  EdicaoMetaSoberana,
  EscopoMetasSoberanas,
  ExclusaoMetaSoberana,
  FinalizacaoMetaSoberana,
  GoalRepository,
  LimiteSoberano,
  LimitesDoSoberanos,
  MetaMutadaSoberana,
  MetaSoberana,
  NovaMetaSoberana,
  OperacaoIdempotente,
  ProgressoMetaSoberana,
  RelacaoMetaSoberana,
  ResultadoMetas,
  RevisaoFinalizacaoMetaSoberana,
} from "../../../application/ports/GoalRepository";
import type { StatusCicloAvaliacao } from "../../../types/CicloAvaliacao";
import type { StatusMeta } from "../../../types/Meta";
import { ehUuid, type CodigoPublico, type PapelAprovacaoMeta, type TipoMetaSoberana } from "./contrato";
import type { EdgeMetas, ResultadoEdgeMetas } from "./edgeMetas";

const ERRO_SEM_ORGANIZACAO = "Organização ativa ausente.";
const ERRO_META_INVALIDA = "Identificador de meta inválido.";
const ERRO_CICLO_INVALIDO = "Identificador de ciclo inválido.";
const ERRO_RESPOSTA = "Resposta inesperada do servidor.";

/** Vocabulários fechados dos CHECK do schema (§6.2) — nada é derivado de texto livre. */
const TIPOS: readonly TipoMetaSoberana[] = ["NEGOCIO_PROJETO", "INDIVIDUAL"];
const PAPEIS: readonly PapelAprovacaoMeta[] = ["GERENTE", "COORDENADOR"];
const STATUS: readonly StatusMeta[] = ["EM_ANDAMENTO", "ATINGIDA", "NAO_ATINGIDA"];
const RELACOES: readonly RelacaoMetaSoberana[] = [
  "SELF",
  "APROVADOR_GERENTE_CONGELADO",
  "APROVADOR_COORDENADOR_CONGELADO",
];
const STATUS_CICLO: readonly StatusCicloAvaliacao[] = [
  "PLANEJADO",
  "ATIVO",
  "ENCERRADO",
  "CANCELADO",
];

function ehRegistro(valor: unknown): valor is Record<string, unknown> {
  return typeof valor === "object" && valor !== null && !Array.isArray(valor);
}

function ehTexto(valor: unknown): valor is string {
  return typeof valor === "string";
}

function ehVersao(valor: unknown): valor is number {
  return typeof valor === "number" && Number.isInteger(valor) && valor >= 0;
}

function ehTipo(valor: unknown): valor is TipoMetaSoberana {
  return typeof valor === "string" && (TIPOS as readonly string[]).includes(valor);
}

function ehPapel(valor: unknown): valor is PapelAprovacaoMeta {
  return typeof valor === "string" && (PAPEIS as readonly string[]).includes(valor);
}

function ehStatus(valor: unknown): valor is StatusMeta {
  return typeof valor === "string" && (STATUS as readonly string[]).includes(valor);
}

function ehRelacao(valor: unknown): valor is RelacaoMetaSoberana {
  return typeof valor === "string" && (RELACOES as readonly string[]).includes(valor);
}

/** Texto possivelmente nulo (coluna anulável): `undefined` = fora do contrato. */
function textoOuNulo(valor: unknown): string | null | undefined {
  if (valor === null) return null;
  return ehTexto(valor) ? valor : undefined;
}

/** Inteiro possivelmente nulo: `undefined` = fora do contrato. */
function inteiroOuNulo(valor: unknown): number | null | undefined {
  if (valor === null) return null;
  return ehVersao(valor) ? valor : undefined;
}

/** UUID possivelmente nulo (identidade soberana): `undefined` = fora do contrato. */
function uuidOuNulo(valor: unknown): string | null | undefined {
  if (valor === null) return null;
  return ehUuid(valor) ? valor.trim() : undefined;
}

/** Status soberano do ciclo: valor fora do domínio conhecido vira `null`. */
function statusDoCiclo(valor: unknown): StatusCicloAvaliacao | null {
  return typeof valor === "string" && (STATUS_CICLO as readonly string[]).includes(valor)
    ? (valor as StatusCicloAvaliacao)
    : null;
}

/** Aprovações VIGENTES da meta; `null` = payload fora do contrato (linha descartada). */
function mapearAprovacoes(valor: unknown): readonly AprovacaoVigenteSoberana[] | null {
  if (!Array.isArray(valor)) return null;
  const aprovacoes: AprovacaoVigenteSoberana[] = [];
  for (const item of valor) {
    if (!ehRegistro(item)) return null;
    const aprovacaoId = item.aprovacao_id;
    const papel = item.papel;
    const decididoEm = item.decidido_em;
    const motivo = textoOuNulo(item.motivo);
    if (!ehUuid(aprovacaoId) || !ehPapel(papel) || !ehTexto(decididoEm)) return null;
    if (motivo === undefined) return null;
    aprovacoes.push({
      papel,
      aprovacaoId: aprovacaoId.trim(),
      decididoEm,
      motivo,
    });
  }
  return aprovacoes;
}

/**
 * Aprovações POR PAPEL da meta (§4 do contrato P5.2): a superfície devolve SEMPRE
 * os dois papéis (`PAPEIS`), e `papel`/`exigida`/`vigente` são FATOS — o
 * repositório só os transporta, nunca reconstrói a regra (D15/§4).
 *
 * Fail-closed: item que não é registro, papel desconhecido, campo com tipo
 * inesperado, papel AUSENTE ou REPETIDO ⇒ `null`, e a LINHA inteira é descartada
 * — nada é normalizado nem completado com valor inventado (mesmo padrão das
 * demais colunas). A ambiguidade documentada em §4 (`exigida` do COORDENADOR)
 * permanece FATO da RPC: aqui não há inferência.
 */
function mapearAprovacoesSoberanas(valor: unknown): readonly AprovacaoSoberana[] | null {
  if (!Array.isArray(valor)) return null;
  const aprovacoes: AprovacaoSoberana[] = [];
  for (const item of valor) {
    if (!ehRegistro(item)) return null;
    const papel = item.papel;
    const exigida = item.exigida;
    const vigente = item.vigente;
    const aprovacaoId = uuidOuNulo(item.aprovacao_id);
    const decididoEm = textoOuNulo(item.decidido_em);
    const motivo = textoOuNulo(item.motivo);
    const aprovadorCollaboratorId = uuidOuNulo(item.aprovador_collaborator_id);
    if (!ehPapel(papel)) return null;
    if (typeof exigida !== "boolean" || typeof vigente !== "boolean") return null;
    if (aprovacaoId === undefined || decididoEm === undefined) return null;
    if (motivo === undefined || aprovadorCollaboratorId === undefined) return null;
    aprovacoes.push({
      papel,
      exigida,
      vigente,
      aprovacaoId,
      decididoEm,
      motivo,
      aprovadorCollaboratorId,
    });
  }
  // SEMPRE os dois papéis, cada um exatamente uma vez (§4): ausência ou repetição
  // é contrato violado — a linha é descartada e nada é inventado para o papel que
  // falta (a UI não reconstrói regra).
  if (aprovacoes.length !== PAPEIS.length) return null;
  if (!PAPEIS.every((papel) => aprovacoes.some((item) => item.papel === papel))) return null;
  return aprovacoes;
}

/**
 * Mapeia a meta devolvida pela leitura por escopo, sem derivar identidade de
 * rótulo algum. Linha fora do contrato (id/colaborador/ciclo divergente, tipo,
 * status, relação ou versão inválidos, data de linha ausente/malformada,
 * aprovações por papel malformadas ou incompletas) é DESCARTADA (fail-closed) —
 * nunca normalizada nem completada com valor inventado.
 */
function mapearMeta(
  bruto: unknown,
  organizationId: string,
  cycleId: string
): MetaSoberana | null {
  if (!ehRegistro(bruto)) return null;
  const id = bruto.goal_id;
  if (!ehUuid(id)) return null;
  // Defesa em profundidade (NÃO é autorização): a linha precisa pertencer ao
  // ciclo PEDIDO — o tenant é conferido no envelope e a barreira real é a Edge.
  if (bruto.cycle_id !== cycleId) return null;
  const collaboratorId = bruto.collaborator_id;
  if (!ehUuid(collaboratorId)) return null;

  const tipo = bruto.tipo;
  const descricao = bruto.descricao;
  const kpi = bruto.kpi;
  const valorAlvo = bruto.valor_alvo;
  const status = bruto.status;
  if (!ehTipo(tipo)) return null;
  if (!ehTexto(descricao) || !ehTexto(kpi) || !ehTexto(valorAlvo)) return null;
  if (!ehStatus(status)) return null;

  const progressoPercentual = inteiroOuNulo(bruto.progresso_percentual);
  if (progressoPercentual === undefined) return null;
  if (progressoPercentual !== null && (progressoPercentual < 0 || progressoPercentual > 100)) {
    return null;
  }

  const resultadoAtual = textoOuNulo(bruto.resultado_atual);
  const resultadoFinal = textoOuNulo(bruto.resultado_final);
  if (resultadoAtual === undefined || resultadoFinal === undefined) return null;

  const atingida = bruto.atingida;
  if (atingida !== null && typeof atingida !== "boolean") return null;
  const excluida = bruto.excluida;
  if (typeof excluida !== "boolean") return null;
  const version = bruto.version;
  if (!ehVersao(version)) return null;
  const relacao = bruto.relacao;
  if (!ehRelacao(relacao)) return null;

  const aprovacoesVigentes = mapearAprovacoes(bruto.aprovacoes_vigentes);
  if (aprovacoesVigentes === null) return null;

  // P5.2 (§3): datas soberanas da LINHA. `created_at`/`updated_at` são `not null`
  // no schema, então o fato SEMPRE existe: ausência ou forma inesperada (inclusive
  // `null`) é contrato violado e a linha é DESCARTADA — nunca se inventa data.
  const criadoEm = bruto.criado_em;
  const atualizadoEm = bruto.atualizado_em;
  if (!ehTexto(criadoEm) || !ehTexto(atualizadoEm)) return null;

  // P5.2 (§3): colunas ANULÁVEIS — `null` é ausência REAL do fato. `atualizadoEm`
  // NÃO é "último acompanhamento": são fatos distintos.
  const dataUltimoAcompanhamento = textoOuNulo(bruto.data_ultimo_acompanhamento);
  const dataFechamento = textoOuNulo(bruto.data_fechamento);
  const dataExclusao = textoOuNulo(bruto.data_exclusao);
  if (
    dataUltimoAcompanhamento === undefined ||
    dataFechamento === undefined ||
    dataExclusao === undefined
  ) {
    return null;
  }

  // P5.2 (§4): estado de aprovação POR PAPEL — sempre os dois papéis.
  const aprovacoes = mapearAprovacoesSoberanas(bruto.aprovacoes);
  if (aprovacoes === null) return null;

  return {
    id: id.trim(),
    organizationId,
    cycleId,
    collaboratorId: collaboratorId.trim(),
    tipo,
    descricao,
    kpi,
    valorAlvo,
    status,
    progressoPercentual,
    resultadoAtual,
    resultadoFinal,
    atingida,
    excluida,
    version,
    relacao,
    criadoEm,
    atualizadoEm,
    dataUltimoAcompanhamento,
    dataFechamento,
    dataExclusao,
    aprovacoes,
    aprovacoesVigentes,
  };
}

/**
 * Quotas do CICLO por tipo (§5 do contrato P5.2): array de `{tipo, quantidade,
 * version}`.
 *
 * Fail-closed:
 * - chave AUSENTE (`undefined`), `null` ou `[]` ⇒ `[]`, que é a quota ZERO
 *   EXPLÍCITA para todos os tipos ("ausência de linha = quota ZERO", §5) — nunca
 *   "ilimitado";
 * - linha malformada é DESCARTADA (o tipo fica sem quota ⇒ ZERO), como já
 *   acontece com a linha de meta;
 * - forma inesperada do campo (não-array e não-ausente) ⇒ `null`: envelope fora
 *   do contrato, que vira `INTERNAL` — anomalia NÃO vira quota zero silenciosa.
 */
function mapearLimitesDoEscopo(valor: unknown): readonly LimiteSoberano[] | null {
  if (valor === undefined || valor === null) return [];
  if (!Array.isArray(valor)) return null;
  const limites: LimiteSoberano[] = [];
  for (const item of valor) {
    if (!ehRegistro(item)) continue;
    const tipo = item.tipo;
    const quantidade = item.quantidade;
    const version = item.version;
    if (!ehTipo(tipo) || !ehVersao(quantidade) || !ehVersao(version)) continue;
    limites.push({ tipo, quantidade, version });
  }
  return limites;
}

/**
 * Mapeia o envelope do escopo. Envelope fora do contrato — ou com tenant/ciclo
 * divergente do PEDIDO — é `null`: resposta anômala NÃO vira "não há metas".
 * P5.2 (§5): `limites` (quota do ciclo/tipo) entra na mesma disciplina.
 */
function mapearEscopo(
  bruto: unknown,
  organizationId: string,
  cycleId: string
): EscopoMetasSoberanas | null {
  if (!ehRegistro(bruto)) return null;
  if (bruto.organization_id !== organizationId) return null;
  if (bruto.cycle_id !== cycleId) return null;
  if (!Array.isArray(bruto.metas)) return null;

  const limites = mapearLimitesDoEscopo(bruto.limites);
  if (limites === null) return null;

  const metas = bruto.metas
    .map((item) => mapearMeta(item, organizationId, cycleId))
    .filter((meta): meta is MetaSoberana => meta !== null);

  return {
    organizationId,
    cycleId,
    cicloStatus: statusDoCiclo(bruto.ciclo_status),
    // Derivado das metas ACEITAS (o campo do servidor é redundante e não é
    // autoridade): conjunto vazio é ausência EXPLÍCITA de meta autorizada.
    escopo: metas.length === 0 ? "SEM_META_AUTORIZADA" : "ESCOPO_APLICADO",
    metas,
    // Vazio = quota ZERO para todos os tipos (§5); `usado` é derivado no cliente
    // das próprias metas (relação SELF e `!excluida`), nunca lido de outra via.
    limites,
  };
}

/** Resultado das mutações de meta: `{ goal_id, version, status }` da RPC. */
function mapearMetaMutada(bruto: unknown): MetaMutadaSoberana | null {
  if (!ehRegistro(bruto)) return null;
  const goalId = bruto.goal_id;
  const version = bruto.version;
  const status = bruto.status;
  if (!ehUuid(goalId) || !ehVersao(version) || !ehStatus(status)) return null;
  return { goalId: goalId.trim(), version, status };
}

/** Resultado de `meta_aprovar` (fato de aprovação, D3). */
function mapearAprovacaoRegistrada(bruto: unknown): AprovacaoRegistradaSoberana | null {
  if (!ehRegistro(bruto)) return null;
  const goalId = bruto.goal_id;
  const aprovacaoId = bruto.aprovacao_id;
  const papel = bruto.papel;
  const version = bruto.version;
  const status = bruto.status;
  if (!ehUuid(goalId) || !ehUuid(aprovacaoId)) return null;
  if (!ehPapel(papel) || !ehVersao(version) || !ehStatus(status)) return null;
  return {
    goalId: goalId.trim(),
    aprovacaoId: aprovacaoId.trim(),
    papel,
    version,
    status,
  };
}

/** Resultado de `meta_definir_limites_do_ciclo` (`{ cycle_id, version, tipo, quantidade }`). */
function mapearLimites(bruto: unknown): LimitesDoSoberanos | null {
  if (!ehRegistro(bruto)) return null;
  const cycleId = bruto.cycle_id;
  const version = bruto.version;
  const tipo = bruto.tipo;
  const quantidade = bruto.quantidade;
  if (!ehUuid(cycleId) || !ehVersao(version)) return null;
  if (!ehTipo(tipo) || !ehVersao(quantidade)) return null;
  return {
    cycleId: cycleId.trim(),
    version,
    tipo,
    quantidade,
  };
}

/**
 * Fábrica do repositório. O adapter da Edge é a ÚNICA dependência: sem cliente de
 * tabela, sem RLS direta e sem caminho alternativo (D22-A).
 */
export function criarRepositorioMetasSoberanas(edge: EdgeMetas): GoalRepository {
  function falha<T>(codigo: CodigoPublico, mensagem: string): ResultadoMetas<T> {
    return { ok: false, error: { code: codigo, message: mensagem } };
  }

  function organizacaoValida(organizationId: string): boolean {
    return typeof organizationId === "string" && organizationId.length > 0;
  }

  /** Chave de idempotência: a do chamador (retentativa) ou uma nova (D11). */
  function operationIdDe(opcoes?: OperacaoIdempotente): string {
    return opcoes?.operationId ?? crypto.randomUUID();
  }

  /**
   * Projeta o resultado do adapter: erro público é PROPAGADO sem tradução (o
   * código já é o do contrato) e payload fora do contrato é `INTERNAL`.
   */
  function projetar<T>(
    resultado: ResultadoEdgeMetas<unknown>,
    mapear: (bruto: unknown) => T | null
  ): ResultadoMetas<T> {
    if (!resultado.ok) return resultado;
    const data = mapear(resultado.data);
    if (data === null) return falha("INTERNAL", ERRO_RESPOSTA);
    return { ok: true, data };
  }

  return {
    async listarMetasPorEscopo(organizationId, cycleId, opcoes) {
      if (!organizacaoValida(organizationId)) return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      // UUID-first: o escopo é sempre um CICLO canônico, nunca `ano`/`numero`.
      if (!ehUuid(cycleId)) return falha("INVALID_INPUT", ERRO_CICLO_INVALIDO);

      const resultado = await edge.listarPorEscopo({
        organizationId,
        cycleId,
        operationId: operationIdDe(opcoes),
      });
      return projetar(resultado, (bruto) => mapearEscopo(bruto, organizationId, cycleId));
    },

    async criarMeta(dados: NovaMetaSoberana) {
      if (!organizacaoValida(dados.organizationId)) {
        return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      }
      if (!ehUuid(dados.cycleId)) return falha("INVALID_INPUT", ERRO_CICLO_INVALIDO);

      const resultado = await edge.criar({
        organizationId: dados.organizationId,
        cycleId: dados.cycleId,
        collaboratorId: dados.collaboratorId,
        tipo: dados.tipo,
        descricao: dados.descricao,
        kpi: dados.kpi,
        valorAlvo: dados.valorAlvo,
        operationId: operationIdDe(dados),
      });
      return projetar(resultado, mapearMetaMutada);
    },

    async editarMeta(dados: EdicaoMetaSoberana) {
      if (!organizacaoValida(dados.organizationId)) {
        return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      }
      if (!ehUuid(dados.goalId)) return falha("INVALID_INPUT", ERRO_META_INVALIDA);

      const resultado = await edge.editar({
        organizationId: dados.organizationId,
        goalId: dados.goalId,
        descricao: dados.descricao,
        kpi: dados.kpi,
        valorAlvo: dados.valorAlvo,
        expectedVersion: dados.expectedVersion,
        operationId: operationIdDe(dados),
      });
      return projetar(resultado, mapearMetaMutada);
    },

    async atualizarProgressoMeta(dados: ProgressoMetaSoberana) {
      if (!organizacaoValida(dados.organizationId)) {
        return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      }
      if (!ehUuid(dados.goalId)) return falha("INVALID_INPUT", ERRO_META_INVALIDA);

      const resultado = await edge.atualizarProgresso({
        organizationId: dados.organizationId,
        goalId: dados.goalId,
        resultadoAtual: dados.resultadoAtual,
        progressoPercentual: dados.progressoPercentual,
        expectedVersion: dados.expectedVersion,
        operationId: operationIdDe(dados),
      });
      return projetar(resultado, mapearMetaMutada);
    },

    async finalizarMeta(dados: FinalizacaoMetaSoberana) {
      if (!organizacaoValida(dados.organizationId)) {
        return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      }
      if (!ehUuid(dados.goalId)) return falha("INVALID_INPUT", ERRO_META_INVALIDA);

      const resultado = await edge.finalizar({
        organizationId: dados.organizationId,
        goalId: dados.goalId,
        resultadoFinal: dados.resultadoFinal,
        atingida: dados.atingida,
        expectedVersion: dados.expectedVersion,
        operationId: operationIdDe(dados),
      });
      return projetar(resultado, mapearMetaMutada);
    },

    async revisarFinalizacaoMeta(dados: RevisaoFinalizacaoMetaSoberana) {
      if (!organizacaoValida(dados.organizationId)) {
        return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      }
      if (!ehUuid(dados.goalId)) return falha("INVALID_INPUT", ERRO_META_INVALIDA);

      const resultado = await edge.revisarFinalizacao({
        organizationId: dados.organizationId,
        goalId: dados.goalId,
        resultadoFinal: dados.resultadoFinal,
        atingida: dados.atingida,
        expectedVersion: dados.expectedVersion,
        operationId: operationIdDe(dados),
        ...(dados.motivo === undefined ? {} : { motivo: dados.motivo }),
      });
      return projetar(resultado, mapearMetaMutada);
    },

    async excluirMeta(dados: ExclusaoMetaSoberana) {
      if (!organizacaoValida(dados.organizationId)) {
        return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      }
      if (!ehUuid(dados.goalId)) return falha("INVALID_INPUT", ERRO_META_INVALIDA);

      const resultado = await edge.excluir({
        organizationId: dados.organizationId,
        goalId: dados.goalId,
        motivo: dados.motivo,
        expectedVersion: dados.expectedVersion,
        operationId: operationIdDe(dados),
      });
      return projetar(resultado, mapearMetaMutada);
    },

    async aprovarMeta(dados: AprovacaoMetaSolicitada) {
      if (!organizacaoValida(dados.organizationId)) {
        return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      }
      if (!ehUuid(dados.goalId)) return falha("INVALID_INPUT", ERRO_META_INVALIDA);

      const resultado = await edge.aprovar({
        organizationId: dados.organizationId,
        goalId: dados.goalId,
        papel: dados.papel,
        expectedVersion: dados.expectedVersion,
        operationId: operationIdDe(dados),
        ...(dados.motivo === undefined ? {} : { motivo: dados.motivo }),
      });
      return projetar(resultado, mapearAprovacaoRegistrada);
    },

    async definirLimitesDoCiclo(dados: DefinicaoDeLimitesDoSoberana) {
      if (!organizacaoValida(dados.organizationId)) {
        return falha("FORBIDDEN", ERRO_SEM_ORGANIZACAO);
      }
      if (!ehUuid(dados.cycleId)) return falha("INVALID_INPUT", ERRO_CICLO_INVALIDO);

      const resultado = await edge.definirLimitesDoCiclo({
        organizationId: dados.organizationId,
        cycleId: dados.cycleId,
        tipo: dados.tipo,
        quantidade: dados.quantidade,
        motivo: dados.motivo,
        expectedVersion: dados.expectedVersion,
        operationId: operationIdDe(dados),
      });
      return projetar(resultado, mapearLimites);
    },
  };
}
