/**
 * F5-10 P5 (Issue #218), Bloco 1/S2 — PORTA soberana do domínio de METAS
 * (UUID-first, ASSÍNCRONA, fail-closed).
 *
 * ## Por que a porta existe
 *
 * A autoridade funcional de metas era LOCAL (`src/services/metaStorage.ts` em
 * `localStorage`): a auditoria da F5-10 (§3/§5) classificou esse caminho como
 * resíduo a remover no cutover (P6), nunca contrato produtivo final. A porta
 * descreve a fronteira SOBERANA que o substitui:
 *
 * - **assíncrona**: toda operação devolve `Promise<ResultadoMetas<T>>`;
 * - **UUID-first**: a identidade canônica é `evaluation_goals.id` e o recorte é
 *   por `evaluation_cycles.id`; `ano`/`numero`, matrícula e nome são RÓTULOS de
 *   projeção — nunca identidade, autorização ou chave de leitura (D1/D8);
 * - **fail-closed**: erro/indisponibilidade NUNCA resulta em fallback local,
 *   dual-read ou dado inventado. A ausência é explícita e a falha tem código
 *   público (`CodigoPublico`);
 * - **sem autorização do lado do cliente**: a porta transporta apenas INTENÇÃO
 *   (alvo, versão esperada, campos de domínio, motivo e `operationId`). Nenhuma
 *   decisão de capability, papel ou estado acontece aqui — `actor*`,
 *   `membership*`, `status`, `aprovado`, `capability`, `role`, `cargo` e `funcao`
 *   NÃO existem nesta superfície (D3/D7/D9);
 * - **leitura pela superfície soberana (D22-A)**: por decisão do Bloco 1 desta
 *   Issue, a leitura de metas NÃO usa PostgREST/RLS direto — `SELECT` own-tenant
 *   não é autorização funcional (§11) e a RLS de metas será revogada para
 *   `authenticated` no Bloco 2. Toda leitura passa por `goal.listar_por_escopo`,
 *   implementada pelo adapter da Edge.
 *
 * `operationId` é a CHAVE DE IDEMPOTÊNCIA do contrato (D11), gerada no cliente
 * quando ausente — repetir a MESMA intenção com o mesmo id é seguro. Não é
 * identidade de meta.
 *
 * O que esta porta NÃO faz: lifecycle (`status`, revisão de fechamento), quota,
 * aprovação relacional congelada, invalidação, comparação de versão, transação,
 * auditoria e autorização. Tudo isso pertence às RPCs soberanas (§13), pelas
 * quais a Edge é a única via.
 */

import type {
  CodigoPublico,
  PapelAprovacaoMeta,
  TipoMetaSoberana,
} from "../../infrastructure/supabase/metas/contrato";
import type { StatusCicloAvaliacao } from "../../types/CicloAvaliacao";
import type { StatusMeta } from "../../types/Meta";

/** Erro público: código estável + mensagem sem detalhe do banco. */
export interface ErroMetasSoberanos {
  readonly code: CodigoPublico;
  readonly message: string;
}

/** Resultado da porta: sucesso com dados ou falha com código público. */
export type ResultadoMetas<T> =
  | { readonly ok: true; readonly data: T }
  | { readonly ok: false; readonly error: ErroMetasSoberanos };

/** Relação do ator com a meta autorizada (vocabulário de §9.1/§11). */
export type RelacaoMetaSoberana =
  | "SELF"
  | "APROVADOR_GERENTE_CONGELADO"
  | "APROVADOR_COORDENADOR_CONGELADO";

/** Aprovação VIGENTE (fato de `evaluation_goal_approvals`, nunca campo do cliente). */
export interface AprovacaoVigenteSoberana {
  readonly papel: PapelAprovacaoMeta;
  readonly aprovacaoId: string;
  readonly decididoEm: string;
  readonly motivo: string | null;
}

/**
 * Projeção soberana da meta lida pela RPC de escopo (§11/D22): exatamente os
 * campos que a superfície devolve — nada é inventado (sem `ano`/`numero`,
 * matrícula, nome ou histórico local).
 */
export interface MetaSoberana {
  readonly id: string;
  readonly organizationId: string;
  readonly cycleId: string;
  readonly collaboratorId: string;
  readonly tipo: TipoMetaSoberana;
  readonly descricao: string;
  readonly kpi: string;
  readonly valorAlvo: string;
  readonly status: StatusMeta;
  readonly progressoPercentual: number | null;
  readonly resultadoAtual: string | null;
  readonly resultadoFinal: string | null;
  readonly atingida: boolean | null;
  readonly excluida: boolean;
  /** Versão otimista da linha (base de `expectedVersion` — D12). */
  readonly version: number;
  readonly relacao: RelacaoMetaSoberana;
  readonly aprovacoesVigentes: readonly AprovacaoVigenteSoberana[];
}

/**
 * Recorte de escopo devolvido pela leitura (§11): o ator recebe SOMENTE as metas
 * em que é o dono (SELF) ou o aprovador CONGELADO. Conjunto vazio é ausência
 * EXPLÍCITA de meta autorizada — nunca negação silenciosa.
 */
export interface EscopoMetasSoberanas {
  readonly organizationId: string;
  readonly cycleId: string;
  /** Status soberano do ciclo (nulo quando fora do domínio conhecido). */
  readonly cicloStatus: StatusCicloAvaliacao | null;
  readonly escopo: "SEM_META_AUTORIZADA" | "ESCOPO_APLICADO";
  readonly metas: readonly MetaSoberana[];
}

/** Meta mutada: o `resultado` bruto da RPC projetado (sem campos inventados). */
export interface MetaMutadaSoberana {
  readonly goalId: string;
  readonly version: number;
  readonly status: StatusMeta;
}

/** Aprovação registrada (D3: aprovação é FATO; `status` não a codifica). */
export interface AprovacaoRegistradaSoberana {
  readonly goalId: string;
  readonly aprovacaoId: string;
  readonly papel: PapelAprovacaoMeta;
  readonly version: number;
  readonly status: StatusMeta;
}

/** Limites (quota) do ciclo após a operação soberana — versão DO CICLO (D21). */
export interface LimitesDoSoberanos {
  readonly cycleId: string;
  readonly version: number;
  readonly tipo: TipoMetaSoberana;
  readonly quantidade: number;
}

/** Chave de idempotência OPCIONAL (gerada pelo adaptador quando ausente — D11). */
export interface OperacaoIdempotente {
  readonly operationId?: string;
}

/** `goal.criar`: o dono é a INTENÇÃO; SELF é revalidado server-side (D9). */
export interface NovaMetaSoberana extends OperacaoIdempotente {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly collaboratorId: string;
  readonly tipo: TipoMetaSoberana;
  readonly descricao: string;
  readonly kpi: string;
  readonly valorAlvo: string;
}

/** `goal.editar`: definição COMPLETA (não há edição parcial — sem merge local). */
export interface EdicaoMetaSoberana extends OperacaoIdempotente {
  readonly organizationId: string;
  readonly goalId: string;
  readonly descricao: string;
  readonly kpi: string;
  readonly valorAlvo: string;
  readonly expectedVersion: number;
}

export interface ProgressoMetaSoberana extends OperacaoIdempotente {
  readonly organizationId: string;
  readonly goalId: string;
  readonly resultadoAtual: string;
  readonly progressoPercentual: number;
  readonly expectedVersion: number;
}

export interface FinalizacaoMetaSoberana extends OperacaoIdempotente {
  readonly organizationId: string;
  readonly goalId: string;
  readonly resultadoFinal: string;
  readonly atingida: boolean;
  readonly expectedVersion: number;
}

export interface RevisaoFinalizacaoMetaSoberana extends FinalizacaoMetaSoberana {
  readonly motivo?: string;
}

export interface ExclusaoMetaSoberana extends OperacaoIdempotente {
  readonly organizationId: string;
  readonly goalId: string;
  readonly motivo: string;
  readonly expectedVersion: number;
}

export interface AprovacaoMetaSolicitada extends OperacaoIdempotente {
  readonly organizationId: string;
  readonly goalId: string;
  readonly papel: PapelAprovacaoMeta;
  readonly expectedVersion: number;
  readonly motivo?: string;
}

export interface DefinicaoDeLimitesDoSoberana extends OperacaoIdempotente {
  readonly organizationId: string;
  readonly cycleId: string;
  readonly tipo: TipoMetaSoberana;
  readonly quantidade: number;
  readonly motivo: string;
  /** Versão do CICLO (D21), não de uma meta. */
  readonly expectedVersion: number;
}

/**
 * Porta única do domínio de metas: LEITURA por escopo e MUTAÇÕES soberanas.
 *
 * Sem estado, sem cache e sem autorização: a organização é INTENÇÃO de UX e a
 * decisão é sempre da fronteira (Edge `metas`) — a implementação atravessa
 * EXCLUSIVAMENTE o adapter da Edge (D22-A), nunca tabela/RLS direta.
 */
export interface GoalRepository {
  /**
   * Metas do ciclo em que o ator é dono (SELF) ou aprovador CONGELADO —
   * `goal.listar_por_escopo` (§11/D22-A).
   */
  listarMetasPorEscopo(
    organizationId: string,
    cycleId: string,
    opcoes?: OperacaoIdempotente
  ): Promise<ResultadoMetas<EscopoMetasSoberanas>>;
  criarMeta(dados: NovaMetaSoberana): Promise<ResultadoMetas<MetaMutadaSoberana>>;
  editarMeta(dados: EdicaoMetaSoberana): Promise<ResultadoMetas<MetaMutadaSoberana>>;
  atualizarProgressoMeta(
    dados: ProgressoMetaSoberana
  ): Promise<ResultadoMetas<MetaMutadaSoberana>>;
  finalizarMeta(dados: FinalizacaoMetaSoberana): Promise<ResultadoMetas<MetaMutadaSoberana>>;
  revisarFinalizacaoMeta(
    dados: RevisaoFinalizacaoMetaSoberana
  ): Promise<ResultadoMetas<MetaMutadaSoberana>>;
  excluirMeta(dados: ExclusaoMetaSoberana): Promise<ResultadoMetas<MetaMutadaSoberana>>;
  aprovarMeta(
    dados: AprovacaoMetaSolicitada
  ): Promise<ResultadoMetas<AprovacaoRegistradaSoberana>>;
  definirLimitesDoCiclo(
    dados: DefinicaoDeLimitesDoSoberana
  ): Promise<ResultadoMetas<LimitesDoSoberanos>>;
}
