/**
 * F5-10 P5 (Issue #218), Bloco 1/S2 — PORTA soberana do domínio de METAS
 * (UUID-first, ASSÍNCRONA, fail-closed).
 *
 * ## Por que a porta existe
 *
 * A autoridade funcional de metas era LOCAL (`src/services/metaStorage.ts` em
 * `localStorage`): a auditoria da F5-10 (§3/§5) classificou esse caminho como
 * resíduo a remover no cutover (P6), nunca contrato produtivo final. O P6 (Issue #220) executou essa remocao: o dominio de metas nao tem mais leitura nem escrita no armazenamento do navegador. A porta
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
 *
 * ## P5.2 (Issue #222) — projeção AMPLIADA, estritamente ADITIVA
 *
 * A operação `goal.listar_por_escopo`, o conjunto autorizado (`SELF` ∪ aprovador
 * CONGELADO), as capabilities e a RLS NÃO mudaram (§1 do contrato
 * `docs/F5-10-P5.2-contrato-leitura-soberana-metas.md`): o que a P5.2 acrescenta
 * são FATOS que faltavam à projeção — as datas soberanas da linha, o estado de
 * aprovação POR PAPEL (`aprovacoes[]`, sempre os dois papéis — §4) e a quota do
 * CICLO/tipo (`limites[]` — §5). Nada foi removido: `aprovacoesVigentes[]`
 * permanece para compatibilidade.
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
 * Estado de aprovação POR PAPEL (§4 do contrato P5.2): a projeção traz SEMPRE os
 * dois papéis (`GERENTE` e `COORDENADOR`), com o fato já decidido pela RPC.
 *
 * `papel` e `exigida` são **FATOS** — a UI NÃO reconstrói regra (D15/§4):
 * `vigente` ⇒ *concedida*; `!vigente && exigida` ⇒ *exigida e pendente*;
 * `!vigente && !exigida` ⇒ *não exigida*. Nenhuma decisão de autorização
 * acontece nesta superfície.
 *
 * **Limitação registrada (§4), fail-closed e sem autoridade nova:** `exigida` do
 * `COORDENADOR` é `false` tanto para "coordenador não distinto da cadeia" quanto
 * para "estrutura congelada não reconhecida" — a fonte
 * (`f5_10_aprovador_congelado`) devolve `NULL` nos DOIS casos, e distingui-los
 * exigiria duplicar a regra de P3 na leitura. O caminho de MUTAÇÃO continua
 * fail-closed (`meta_aprovar` recusa papel não reconhecido), então o estado
 * ambíguo nunca vira aprovação.
 *
 * `aprovadorCollaboratorId` é a identidade SOBERANA (`collaborators.id`); o NOME
 * é apresentação e é resolvido pela superfície soberana de colaboradores (F5-07)
 * a partir do UUID — nunca projetado aqui (decisão 6).
 */
export interface AprovacaoSoberana {
  readonly papel: PapelAprovacaoMeta;
  readonly exigida: boolean;
  readonly vigente: boolean;
  /** Fato da aprovação vigente (D3); `null` quando não há decisão vigente. */
  readonly aprovacaoId: string | null;
  readonly decididoEm: string | null;
  readonly motivo: string | null;
  readonly aprovadorCollaboratorId: string | null;
}

/**
 * Projeção soberana da meta lida pela RPC de escopo (§11/D22, AMPLIADA na
 * P5.2/§3): exatamente os campos que a superfície devolve — nada é inventado
 * (sem `ano`/`numero`, matrícula, nome ou histórico local).
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
  /**
   * Datas soberanas da LINHA (§3): `created_at`/`updated_at` são `not null` no
   * schema, então o FATO sempre existe e a projeção não as admite nulas —
   * ausência ou forma inesperada é violação de contrato (linha descartada).
   * `atualizadoEm` é a data da LINHA e **NÃO** significa "último acompanhamento".
   */
  readonly criadoEm: string;
  readonly atualizadoEm: string;
  /** Datas de coluna ANULÁVEL: `null` é ausência REAL do fato (§3). */
  readonly dataUltimoAcompanhamento: string | null;
  readonly dataFechamento: string | null;
  readonly dataExclusao: string | null;
  /** Estado de aprovação por papel — SEMPRE os dois papéis (§4). */
  readonly aprovacoes: readonly AprovacaoSoberana[];
  readonly aprovacoesVigentes: readonly AprovacaoVigenteSoberana[];
}

/**
 * Quota soberana do CICLO por TIPO (§5 do contrato P5.2, de
 * `evaluation_cycle_goal_limits`): o limite é do **CICLO/tipo** — NUNCA "por
 * colaborador" (a unicidade viva da meta é por DONO) — e `version` é a versão da
 * LINHA de limite (base do `expectedVersion` de `goal.definir_limites_do_ciclo`,
 * D21), não da meta.
 *
 * **AUSÊNCIA de linha = quota ZERO** (fail-closed, §5): `limites` vazio significa
 * "nenhuma quota configurada" para TODOS os tipos, jamais "ilimitado". O consumo
 * (`usado`) NÃO é projetado: é derivado no cliente das PRÓPRIAS metas lidas
 * (relação `SELF` e `!excluida`).
 */
export interface LimiteSoberano {
  readonly tipo: TipoMetaSoberana;
  readonly quantidade: number;
  readonly version: number;
}

/**
 * Recorte de escopo devolvido pela leitura (§11, AMPLIADO na P5.2/§5): o ator
 * recebe SOMENTE as metas em que é o dono (SELF) ou o aprovador CONGELADO.
 * Conjunto vazio é ausência EXPLÍCITA de meta autorizada — nunca negação
 * silenciosa.
 */
export interface EscopoMetasSoberanas {
  readonly organizationId: string;
  readonly cycleId: string;
  /** Status soberano do ciclo (nulo quando fora do domínio conhecido). */
  readonly cicloStatus: StatusCicloAvaliacao | null;
  readonly escopo: "SEM_META_AUTORIZADA" | "ESCOPO_APLICADO";
  readonly metas: readonly MetaSoberana[];
  /** Quotas do ciclo por tipo; vazio = quota ZERO para todos (§5). */
  readonly limites: readonly LimiteSoberano[];
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
